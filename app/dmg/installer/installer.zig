const std = @import("std");

const c = @cImport({
    @cInclude("unistd.h");
});

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    if (args.len >= 2 and std.mem.eql(u8, args[1], "--install")) {
        if (args.len < 4) return usage(args[0]);
        try installApp(init.io, allocator, args[2], args[3]);
        return;
    }

    if (args.len >= 2 and std.mem.eql(u8, args[1], "--register")) {
        if (args.len < 3) return usage(args[0]);
        try registerApp(init.io, args[2]);
        return;
    }

    usage(args[0]);
}

fn usage(exe_name: []const u8) void {
    std.debug.print(
        \\Rosette installer helper
        \\
        \\Usage:
        \\  {s} --install <payload-Rosette.app> <destination-directory>
        \\  {s} --register <installed-Rosette.app>
        \\
    , .{ exe_name, exe_name });
}

fn installApp(io: std.Io, allocator: std.mem.Allocator, payload_app: []const u8, destination_dir: []const u8) !void {
    const target_app = try std.fs.path.join(allocator, &.{ destination_dir, "Rosette.app" });

    std.debug.print("Verifying Rosette payload helpers...\n", .{});
    try verifyPayload(payload_app, allocator);

    std.debug.print("Preparing destination: {s}\n", .{destination_dir});
    try runCmd(io, &[_][]const u8{ "mkdir", "-p", destination_dir });

    std.debug.print("Removing old copy, if present: {s}\n", .{target_app});
    try runCmd(io, &[_][]const u8{ "rm", "-rf", target_app });

    std.debug.print("Copying Rosette.app...\n", .{});
    try runCmd(io, &[_][]const u8{ "cp", "-R", payload_app, destination_dir });

    std.debug.print("Registering file associations...\n", .{});
    registerApp(io, target_app) catch |err| {
        std.debug.print("Finder registration skipped: {s}\n", .{@errorName(err)});
    };

    std.debug.print("Installing Rosette global shell integration...\n", .{});
    std.debug.print("  installing ~/.rosette/bin/rosette and rosette-shell\n", .{});
    std.debug.print("  installing ~/.rosette/bin/elf_processor for make run and ./program\n", .{});
    std.debug.print("  installing default ~/.rosette/config.toml with dump_results=\"auto\"\n", .{});
    try installShell(io, allocator, target_app);

    std.debug.print("Installation complete: {s}\n", .{target_app});
    std.debug.print("Try from an assignment folder: make run or ./program\n", .{});
}

fn installShell(io: std.Io, allocator: std.mem.Allocator, app_path: []const u8) !void {
    const helper = try std.fs.path.join(allocator, &.{ app_path, "Contents", "MacOS", "rosette-shell" });
    const runtime_root = try std.fs.path.join(allocator, &.{ app_path, "Contents", "Resources", "rosette-runtime" });
    if (!pathExists(allocator, helper)) return error.MissingShellHelper;
    if (!pathExists(allocator, runtime_root)) return error.MissingRuntimeRoot;
    try runCmd(io, &[_][]const u8{ helper, "install", runtime_root });
}

fn verifyPayload(payload_app: []const u8, allocator: std.mem.Allocator) !void {
    const required = [_][]const u8{
        "Contents/MacOS/rosette",
        "Contents/MacOS/rosette-cli",
        "Contents/MacOS/rosette-shell",
        "Contents/MacOS/elf_processor",
        "Contents/MacOS/rosette_assembler_runner",
        "Contents/MacOS/rosette-exec.dylib",
        "Contents/Resources/rosette-runtime/GNUmakefile",
        "Contents/Resources/rosette-runtime/src/shell/global_config/rosette_shell.zig",
        "Contents/Resources/rosette-runtime/ELF_processor/process.zig",
    };

    for (required) |relative| {
        const path = try std.fs.path.join(allocator, &.{ payload_app, relative });
        if (!pathExists(allocator, path)) {
            std.debug.print("missing payload item: {s}\n", .{path});
            return error.MissingPayloadItem;
        }
    }
}

fn registerApp(io: std.Io, app_path: []const u8) !void {
    try runCmd(io, &[_][]const u8{
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
        "-f",
        app_path,
    });
}

fn runCmd(io: std.Io, argv: []const []const u8) !void {
    var child = try std.process.spawn(io, .{
        .argv = argv,
        .stdout = .inherit,
        .stderr = .inherit,
    });
    const term = try child.wait(io);
    switch (term) {
        .exited => |code| if (code != 0) return error.CommandFailed,
        else => return error.CommandFailed,
    }
}

fn pathExists(allocator: std.mem.Allocator, path: []const u8) bool {
    const path_z = allocator.dupeZ(u8, path) catch return false;
    return c.access(path_z.ptr, 0) == 0;
}
