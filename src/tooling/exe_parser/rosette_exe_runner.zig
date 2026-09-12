const std = @import("std");
const builtin = @import("builtin");
const core = @import("exe_runner_core.zig");

fn bootWrite(text: []const u8) void {
    _ = std.c.write(2, text.ptr, text.len);
}

/// Say, in the first three lines of every run, how this binary was compiled.
///
/// `app/bundling/build.zig` asks for its optimize mode with
/// `standardOptimizeOption(.{ .preferred_optimize_mode = .ReleaseFast })`,
/// which means ReleaseFast *only when the release option is passed* and
/// Debug otherwise. Both Makefile targets that build this runner omitted it,
/// so the binary the Xenia launcher executes was an unoptimized build with
/// runtime safety checks on every arithmetic operation - while every other
/// route, and the name of the variable, said ReleaseFast.
///
/// An interpreter is the worst possible thing to build that way, and nothing
/// in the log said so: the throughput simply looked like the workload. This
/// line makes the build mode part of the evidence, so a timing figure can
/// never again be read without knowing what produced it.
fn bootReportOptimizeMode() void {
    bootWrite(switch (builtin.mode) {
        .ReleaseFast => "[BOOT] rosette_exe_runner: optimize=ReleaseFast\n",
        .ReleaseSafe => "[BOOT] rosette_exe_runner: optimize=ReleaseSafe (safety checks on; throughput is not representative)\n",
        .ReleaseSmall => "[BOOT] rosette_exe_runner: optimize=ReleaseSmall (optimized for size; throughput is not representative)\n",
        .Debug => "[BOOT] rosette_exe_runner: optimize=Debug -- WARNING: this binary is unoptimized and runs every safety check. Interpreter throughput is several times lower than a release build and no timing in this run is representative. Build it with `make exe-runner-build`, which passes -Drelease=true\n",
    });
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

/// Xenia selects its loader from the guest path's extension. Rosette may be
/// handed a retained backup such as `title.iso.backup-20260906...`; keep the
/// host backup as the authority, but expose the original `.iso` identity to
/// the Windows process so `RunTitle` takes the XISO branch.
fn guestMediaName(media_name: []const u8) []const u8 {
    const iso_marker = std.ascii.indexOfIgnoreCase(media_name, ".iso") orelse return media_name;
    return media_name[0 .. iso_marker + 4];
}

fn guestMediaTarget(allocator: std.mem.Allocator, media_name: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator, "C:\\xenia\\{s}", .{guestMediaName(media_name)});
}

fn hasGuestTarget(args: []const []const u8) bool {
    for (args) |arg| {
        if (std.mem.startsWith(u8, arg, "C:\\xenia\\")) return true;
    }
    return false;
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
    bootReportOptimizeMode();

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
    // case: when no guest target was supplied, launch the image under the
    // confined C:\\xenia virtual root using the same leaf name. This remains
    // true when a caller also supplies Xenia flags such as --log_level=1. The
    // PE capsule's Win32 argument bridge reliably preserves this as Xenia's
    // positional target; the named `--target=...` spelling reaches the GUI
    // but does not consistently enter the title-launch path. Keep the
    // authority path and the guest-visible target as separate concerns.
    if (parsed.media_path != null and !hasGuestTarget(parsed.windows_args.items)) {
        const media_name = std.fs.path.basename(parsed.media_path.?);
        if (media_name.len == 0) {
            std.debug.print("--media path has no file name\n", .{});
            usage(args[0]);
            return error.InvalidArgument;
        }
        const target = try guestMediaTarget(allocator, media_name);
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

test "retained media backups keep their XISO guest extension" {
    try std.testing.expectEqualStrings(
        "8CEB1ABA7AC20BDAF62EEA16699E0227.iso",
        guestMediaName("8CEB1ABA7AC20BDAF62EEA16699E0227.iso.backup-20260906T044227Z-17816"),
    );
    try std.testing.expectEqualStrings("title.iso", guestMediaName("title.iso"));
    try std.testing.expectEqualStrings("title.bin", guestMediaName("title.bin"));
}

test "media convenience target is a positional guest path" {
    const target = try guestMediaTarget(
        std.testing.allocator,
        "8CEB1ABA7AC20BDAF62EEA16699E0227.iso.backup-20260906T044227Z-17816",
    );
    defer std.testing.allocator.free(target);
    try std.testing.expectEqualStrings(
        "C:\\xenia\\8CEB1ABA7AC20BDAF62EEA16699E0227.iso",
        target,
    );
    try std.testing.expect(!std.mem.startsWith(u8, target, "--target="));
}
