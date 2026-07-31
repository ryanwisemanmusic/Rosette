const std = @import("std");
const ps1 = @import("root.zig");

const Ps1Translator = ps1.Ps1Translator;

fn usage(exe_name: []const u8) void {
    std.debug.print(
        \\Translate Windows PowerShell scripts to POSIX shell or Makefile.
        \\
        \\Usage:
        \\  {s} <file>                   Output POSIX shell script (default)
        \\  {s} <file> --shell           Output POSIX shell script
        \\  {s} <file> --makefile        Output Makefile recipe
        \\  {s} <file> --run             Execute translated script via /bin/sh
        \\  {s} <file> --dry-run         Print the shell script that would be executed
        \\  {s} <file> -o <output>       Write output to file
        \\
        \\Options:
        \\  --target <name>   Makefile target name (default: generated_target)
        \\  --deps <deps...>  Makefile dependencies
        \\
    , .{ exe_name, exe_name, exe_name, exe_name, exe_name, exe_name });
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    if (args.len < 2) {
        usage(if (args.len > 0) args[0] else "ps1_processor");
        std.process.exit(1);
    }

    const file_path = args[1];

    var mode_shell: bool = true;
    var mode_makefile: bool = false;
    var mode_run: bool = false;
    var mode_dry_run: bool = false;
    var output_path: ?[]const u8 = null;
    var make_target: []const u8 = "generated_target";
    var deps: std.ArrayListUnmanaged([]const u8) = .{ .items = &.{}, .capacity = 0 };
    defer deps.deinit(allocator);

    var i: usize = 2;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--shell")) {
            mode_shell = true;
            mode_makefile = false;
        } else if (std.mem.eql(u8, arg, "--makefile")) {
            mode_makefile = true;
            mode_shell = false;
        } else if (std.mem.eql(u8, arg, "--run")) {
            mode_run = true;
        } else if (std.mem.eql(u8, arg, "--dry-run")) {
            mode_dry_run = true;
        } else if (std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--output")) {
            i += 1;
            if (i >= args.len) {
                std.debug.print("error: -o requires a filename\n", .{});
                std.process.exit(1);
            }
            output_path = args[i];
        } else if (std.mem.eql(u8, arg, "--target")) {
            i += 1;
            if (i >= args.len) {
                std.debug.print("error: --target requires a target name\n", .{});
                std.process.exit(1);
            }
            make_target = args[i];
        } else if (std.mem.eql(u8, arg, "--deps")) {
            i += 1;
            while (i < args.len and !std.mem.startsWith(u8, args[i], "--")) : (i += 1) {
                try deps.append(allocator, args[i]);
            }
            if (i < args.len) i -= 1;
        } else {
            std.debug.print("Unknown argument: {s}\n", .{arg});
            usage(args[0]);
            std.process.exit(1);
        }
    }

    // --run / --dry-run always use shell mode
    if (mode_dry_run or mode_run) {
        mode_shell = true;
        mode_makefile = false;
    }

    // Read the .ps1 file
    const source = std.Io.Dir.cwd().readFileAlloc(init.io, file_path, allocator, .unlimited) catch |err| {
        std.debug.print("error: cannot read '{s}': {}\n", .{ file_path, err });
        std.process.exit(1);
    };

    var translator = Ps1Translator.init(allocator);
    defer translator.deinit();

    translator.parse(source) catch |err| {
        std.debug.print("error: parse failed: {}\n", .{err});
        std.process.exit(1);
    };

    // Build output into buffer
    var out_buf: std.ArrayListUnmanaged(u8) = .{ .items = &.{}, .capacity = 0 };
    defer out_buf.deinit(allocator);

    if (mode_makefile) {
        try translator.toMakefile(make_target, deps.items, &out_buf);
    } else {
        try translator.toShell(true, &out_buf);
    }

    if (mode_dry_run) {
        try writeAllStdout(init, out_buf.items);
        return;
    }

    if (mode_run) {
        // Build shell script without shebang for piping to /bin/sh
        var script_buf: std.ArrayListUnmanaged(u8) = .{ .items = &.{}, .capacity = 0 };
        defer script_buf.deinit(allocator);
        try translator.toShell(false, &script_buf);

        var spawn_opts: std.process.SpawnOptions = .{
            .argv = &.{"/bin/sh"},
            .stdin = .pipe,
            .stdout = .inherit,
            .stderr = .inherit,
        };
        if (std.fs.path.dirname(file_path)) |wd| {
            spawn_opts.cwd = .{ .path = wd };
        }
        var child = try std.process.spawn(init.io, spawn_opts);
        {
            var stdin_buf: [4096]u8 = undefined;
            var stdin_writer = child.stdin.?.writer(init.io, &stdin_buf);
            const stdin_w = &stdin_writer.interface;
            try stdin_w.writeAll(script_buf.items);
            try stdin_writer.flush();
        }
        child.stdin.?.close(init.io);
        child.stdin = null;

        const result = try child.wait(init.io);
        switch (result) {
            .exited => |code| {
                if (code != 0) std.process.exit(@intCast(code));
            },
            else => std.process.exit(1),
        }
        return;
    }

    if (output_path) |path| {
        var out_file = try std.Io.Dir.cwd().createFile(init.io, path, .{});
        defer out_file.close(init.io);
        var file_buf: [4096]u8 = undefined;
        var file_writer = out_file.writer(init.io, &file_buf);
        const file_w = &file_writer.interface;
        try file_w.writeAll(out_buf.items);
        try file_writer.flush();
    } else {
        try writeAllStdout(init, out_buf.items);
    }
}

fn writeAllStdout(init: std.process.Init, data: []const u8) !void {
    const stdout_file = std.Io.File.stdout();
    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = stdout_file.writer(init.io, &stdout_buf);
    const stdout_w = &stdout_writer.interface;
    try stdout_w.writeAll(data);
    if (data.len > 0 and data[data.len - 1] != '\n') {
        try stdout_w.writeByte('\n');
    }
    try stdout_writer.flush();
}
