const std = @import("std");
const core = @import("exe_runner_core.zig");

fn bootWrite(text: []const u8) void {
    _ = std.c.write(2, text.ptr, text.len);
}

fn defaultTraceLogPath(allocator: std.mem.Allocator, exe_path: []const u8) ![:0]u8 {
    const log_text = try std.fmt.allocPrint(allocator, "{s}.trace.log", .{exe_path});
    defer allocator.free(log_text);
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
        \\  {s} --open <program.exe> [--arg <value> ...] [--media <host-path>] [--parse-only]
        \\  {s} <program.exe> [trace.log] [--arg <value> ...] [--media <host-path>] [--parse-only]
        \\
    , .{ exe_name, exe_name });
}

const ParsedLaunchOptions = struct {
    launch_allowed: bool = true,
    windows_args: std.ArrayListUnmanaged([]const u8) = .empty,
    media_path: ?[]const u8 = null,
};

fn isRunnerOption(value: []const u8) bool {
    return std.mem.eql(u8, value, "--parse-only") or
        std.mem.eql(u8, value, "--arg") or
        std.mem.eql(u8, value, "--media");
}

fn parseLaunchOptions(allocator: std.mem.Allocator, args: []const []const u8) !ParsedLaunchOptions {
    var parsed: ParsedLaunchOptions = .{};
    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const value = args[index];
        if (std.mem.eql(u8, value, "--parse-only")) {
            parsed.launch_allowed = false;
        } else if (std.mem.eql(u8, value, "--arg")) {
            index += 1;
            if (index == args.len) {
                std.debug.print("--arg requires a Windows argument\n", .{});
                return error.InvalidArgument;
            }
            try parsed.windows_args.append(allocator, args[index]);
        } else if (std.mem.eql(u8, value, "--media")) {
            index += 1;
            if (index == args.len) {
                std.debug.print("--media requires a host path\n", .{});
                return error.InvalidArgument;
            }
            parsed.media_path = args[index];
        } else {
            std.debug.print("unknown argument: {s}\n", .{value});
            return error.InvalidArgument;
        }
    }
    return parsed;
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
    var option_start: usize = 0;

    if (std.mem.eql(u8, args[1], "--open")) {
        if (args.len < 3) {
            usage(args[0]);
            return error.MissingExePath;
        }
        exe_path = args[2];
        option_start = 3;
    } else {
        exe_path = args[1];
        if (args.len >= 3 and !isRunnerOption(args[2])) {
            trace_arg = args[2];
        }
        option_start = if (trace_arg == null) 2 else 3;
    }

    var parsed = parseLaunchOptions(allocator, args[option_start..]) catch |err| {
        usage(args[0]);
        return err;
    };
    defer parsed.windows_args.deinit(allocator);

    // `--media` is both an authority and a convenience for the common Xenia
    // case: when no explicit target was supplied, launch the image under the
    // confined C:\\xenia virtual root using the same leaf name.
    if (parsed.media_path != null and parsed.windows_args.items.len == 0) {
        const media_name = std.fs.path.basename(parsed.media_path.?);
        if (media_name.len == 0) {
            std.debug.print("--media path has no file name\n", .{});
            usage(args[0]);
            return error.InvalidArgument;
        }
        const target = try std.fmt.allocPrint(allocator, "C:\\xenia\\{s}", .{media_name});
        try parsed.windows_args.append(allocator, target);
    }

    const log_path = if (trace_arg) |path|
        try allocator.dupeZ(u8, path)
    else
        try defaultTraceLogPath(allocator, exe_path);

    try core.runWithArguments(init, exe_path, log_path, parsed.launch_allowed, parsed.windows_args.items, parsed.media_path);
}

test "default trace path follows executable path" {
    const log_path = try defaultTraceLogPath(std.testing.allocator, "assets/exe_examples/Notepad.exe");
    defer std.testing.allocator.free(log_path);
    try std.testing.expectEqualStrings("assets/exe_examples/Notepad.exe.trace.log", log_path);
}
