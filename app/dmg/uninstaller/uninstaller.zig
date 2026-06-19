const std = @import("std");

const c = @cImport({
    @cInclude("unistd.h");
});

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    const app_path = if (args.len >= 3 and std.mem.eql(u8, args[1], "--remove"))
        args[2]
    else if (args.len == 1)
        "/Applications/Rosette.app"
    else {
        usage(args[0]);
        return;
    };

    try removeApp(init.io, allocator, app_path);
}

fn usage(exe_name: []const u8) void {
    std.debug.print(
        \\Rosette uninstaller helper
        \\
        \\Usage:
        \\  {s} --remove <path-to-Rosette.app>
        \\
    , .{exe_name});
}

fn removeApp(io: std.Io, allocator: std.mem.Allocator, app_path: []const u8) !void {
    std.debug.print("Removing Rosette global shell integration...\n", .{});
    std.debug.print("  removing ~/.rosette/bin/rosette, elf_processor, macho_processor, rosette-router, shell hooks, and config\n", .{});
    removeShell(io, allocator, app_path) catch |err| {
        std.debug.print("Shell integration cleanup skipped: {s}\n", .{@errorName(err)});
    };

    std.debug.print("Unregistering Rosette: {s}\n", .{app_path});
    unregisterApp(io, app_path) catch {};

    std.debug.print("Removing app bundle...\n", .{});
    try runCmd(io, &[_][]const u8{ "rm", "-rf", app_path });

    std.debug.print("Removing LaunchAgent metadata...\n", .{});
    try removeLaunchAgent(io);

    std.debug.print("Uninstall complete.\n", .{});
}

fn removeShell(io: std.Io, allocator: std.mem.Allocator, app_path: []const u8) !void {
    const helper = try std.fs.path.join(allocator, &.{ app_path, "Contents", "MacOS", "rosette-shell" });
    if (pathExists(allocator, helper)) {
        try runCmd(io, &[_][]const u8{ helper, "uninstall" });
        return;
    }

    const home = std.c.getenv("HOME") orelse return;
    const fallback = try std.fs.path.join(allocator, &.{ std.mem.sliceTo(home, 0), ".rosette", "bin", "rosette-shell" });
    if (pathExists(allocator, fallback)) {
        try runCmd(io, &[_][]const u8{ fallback, "uninstall" });
    }
}

fn unregisterApp(io: std.Io, app_path: []const u8) !void {
    try runCmd(io, &[_][]const u8{
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
        "-u",
        app_path,
    });
}

fn removeLaunchAgent(io: std.Io) !void {
    const home = std.c.getenv("HOME") orelse return;
    var buf: [512]u8 = undefined;
    const agent_path = try std.fmt.bufPrint(&buf, "{s}/Library/LaunchAgents/com.rosette.translator.plist", .{home});
    try runCmd(io, &[_][]const u8{ "rm", "-f", agent_path });
}

fn pathExists(allocator: std.mem.Allocator, path: []const u8) bool {
    const path_z = allocator.dupeZ(u8, path) catch return false;
    return c.access(path_z.ptr, 0) == 0;
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
