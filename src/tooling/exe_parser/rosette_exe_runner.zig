const std = @import("std");
const core = @import("exe_runner_core.zig");

fn bootWrite(text: []const u8) void {
    _ = std.c.write(2, text.ptr, text.len);
}

fn defaultTraceLogPath(allocator: std.mem.Allocator, exe_path: []const u8) ![:0]u8 {
    const log_text = try std.fmt.allocPrint(allocator, "{s}.trace.log", .{exe_path});
    return allocator.dupeZ(u8, log_text);
}

pub export fn rosette_debug_enabled() c_int {
    return 1;
}

pub export fn rosette_debug_log_path() [*:0]const u8 {
    return "rosette-exe-runner.log";
}

pub export fn rosette_runtime_abi_fail_fast_enabled() c_int {
    return 1;
}

fn usage(exe_name: []const u8) void {
    std.debug.print(
        \\Rosette standalone EXE runner
        \\
        \\Usage:
        \\  {s} --open <program.exe> [--parse-only]
        \\  {s} <program.exe> [trace.log] [--parse-only]
        \\
    , .{ exe_name, exe_name });
}

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    bootWrite("[BOOT] rosette_exe_runner: standalone entry\n");

    if (args.len < 2) {
        usage(if (args.len > 0) args[0] else "rosette_exe_runner");
        return error.MissingExePath;
    }

    var exe_path: []const u8 = undefined;
    var trace_arg: ?[]const u8 = null;
    var launch_allowed = true;

    if (std.mem.eql(u8, args[1], "--open")) {
        if (args.len < 3) {
            usage(args[0]);
            return error.MissingExePath;
        }
        exe_path = args[2];
        for (args[3..]) |arg| {
            if (std.mem.eql(u8, arg, "--parse-only")) {
                launch_allowed = false;
            } else {
                std.debug.print("unknown argument: {s}\n", .{arg});
                usage(args[0]);
                return error.InvalidArgument;
            }
        }
    } else {
        exe_path = args[1];
        if (args.len >= 3 and !std.mem.eql(u8, args[2], "--parse-only")) {
            trace_arg = args[2];
        }
        const option_start: usize = if (trace_arg == null) 2 else 3;
        for (args[option_start..]) |arg| {
            if (std.mem.eql(u8, arg, "--parse-only")) {
                launch_allowed = false;
            } else {
                std.debug.print("unknown argument: {s}\n", .{arg});
                usage(args[0]);
                return error.InvalidArgument;
            }
        }
    }

    const log_path = if (trace_arg) |path|
        try allocator.dupeZ(u8, path)
    else
        try defaultTraceLogPath(allocator, exe_path);

    try core.run(init, exe_path, log_path, launch_allowed);
}

test "default trace path follows executable path" {
    const log_path = try defaultTraceLogPath(std.testing.allocator, "assets/exe_examples/Notepad.exe");
    defer std.testing.allocator.free(log_path);
    try std.testing.expectEqualStrings("assets/exe_examples/Notepad.exe.trace.log", log_path);
}
