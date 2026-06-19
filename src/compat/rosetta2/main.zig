const std = @import("std");
const config = @import("config.zig");
const router = @import("router.zig");
const trace = @import("trace.zig");

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    const base_policy = try loadBasePolicy(init.io, allocator);
    if (args.len < 2) return usage(args[0]);

    if (std.mem.eql(u8, args[1], "help") or std.mem.eql(u8, args[1], "--help")) {
        usage(args[0]);
        return;
    }
    if (std.mem.eql(u8, args[1], "trace-path")) {
        std.debug.print("{s}\n", .{try trace.defaultTracePath(allocator)});
        return;
    }
    if (std.mem.eql(u8, args[1], "diagnose")) {
        const parsed = try parseRouteArgs(allocator, base_policy, args[2..]);
        if (parsed.target == null) return usage(args[0]);
        var policy = parsed.policy;
        policy.dry_run = true;
        try router.diagnoseTarget(init, allocator, parsed.target.?, parsed.target_args, policy);
        return;
    }
    if (std.mem.eql(u8, args[1], "run")) {
        const parsed = try parseRouteArgs(allocator, base_policy, args[2..]);
        if (parsed.target == null) return usage(args[0]);
        const code = try router.runTarget(init, allocator, parsed.target.?, parsed.target_args, parsed.policy);
        std.process.exit(code);
    }

    const parsed = try parseRouteArgs(allocator, base_policy, args[1..]);
    if (parsed.target == null) return usage(args[0]);
    const code = try router.runTarget(init, allocator, parsed.target.?, parsed.target_args, parsed.policy);
    std.process.exit(code);
}

const ParsedRouteArgs = struct {
    policy: router.Policy,
    target: ?[]const u8,
    target_args: []const []const u8,
};

fn loadBasePolicy(io: std.Io, allocator: std.mem.Allocator) !router.Policy {
    const cfg = try config.load(io, allocator);
    var policy = router.Policy{};
    if (cfg.prefer_rosette) |value| policy.prefer_rosette = value;
    if (cfg.allow_rosetta2_fallback) |value| policy.allow_rosetta2_fallback = value;
    if (cfg.prefer_intel_slice) |value| policy.prefer_intel_slice = value;
    if (cfg.strict) |value| applyStrictMode(&policy, value);
    if (cfg.abort_on_fallback) |value| policy.abort_on_fallback = value;
    if (cfg.abort_on_unsupported) |value| policy.abort_on_unsupported = value;
    if (cfg.trace) |value| policy.trace_enabled = value;
    applyEnvironmentPolicy(&policy);
    return policy;
}

fn applyStrictMode(policy: *router.Policy, enabled: bool) void {
    policy.strict_rosette = enabled;
    if (enabled) {
        policy.allow_rosetta2_fallback = false;
        policy.abort_on_fallback = true;
        policy.abort_on_unsupported = true;
    }
}

fn applyEnvironmentPolicy(policy: *router.Policy) void {
    if (getenvBool("ROSETTE_COMPAT_STRICT")) |value| applyStrictMode(policy, value);
    if (getenvBool("ROSETTE_COMPAT_ALLOW_FALLBACK")) |value| policy.allow_rosetta2_fallback = value;
    if (getenvBool("ROSETTE_COMPAT_NO_FALLBACK")) |value| {
        if (value) policy.allow_rosetta2_fallback = false;
    }
    if (getenvBool("ROSETTE_COMPAT_ABORT_ON_FALLBACK")) |value| policy.abort_on_fallback = value;
    if (getenvBool("ROSETTE_COMPAT_ABORT_ON_UNSUPPORTED")) |value| policy.abort_on_unsupported = value;
    if (getenvBool("ROSETTE_COMPAT_ABORT_ON_FAILURE")) |value| policy.abort_on_unsupported = value;
}

fn getenvBool(name: [:0]const u8) ?bool {
    const raw = std.c.getenv(name) orelse return null;
    const value = std.mem.trim(u8, std.mem.sliceTo(raw, 0), " \t\r\n");
    return config.parseBoolText(value);
}

fn parseRouteArgs(allocator: std.mem.Allocator, base_policy: router.Policy, args: []const []const u8) !ParsedRouteArgs {
    var policy = base_policy;
    var target: ?[]const u8 = null;
    var target_args_start: usize = args.len;

    var index: usize = 0;
    while (index < args.len) : (index += 1) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "--")) {
            if (index + 1 < args.len and target == null) {
                target = args[index + 1];
                target_args_start = index + 2;
            } else {
                target_args_start = index + 1;
            }
            break;
        } else if (std.mem.eql(u8, arg, "--dry-run")) {
            policy.dry_run = true;
        } else if (std.mem.eql(u8, arg, "--baseline-rosetta2")) {
            policy.force_apple_rosetta2 = true;
        } else if (std.mem.eql(u8, arg, "--no-fallback")) {
            policy.allow_rosetta2_fallback = false;
        } else if (std.mem.eql(u8, arg, "--allow-fallback")) {
            policy.allow_rosetta2_fallback = true;
        } else if (std.mem.eql(u8, arg, "--strict")) {
            applyStrictMode(&policy, true);
        } else if (std.mem.eql(u8, arg, "--abort-on-fallback")) {
            policy.abort_on_fallback = true;
        } else if (std.mem.eql(u8, arg, "--abort-on-unsupported") or
            std.mem.eql(u8, arg, "--abort-on-failure"))
        {
            policy.abort_on_unsupported = true;
        } else if (std.mem.eql(u8, arg, "--prefer-intel")) {
            policy.prefer_intel_slice = true;
        } else if (std.mem.eql(u8, arg, "--trace-off")) {
            policy.trace_enabled = false;
        } else if (std.mem.eql(u8, arg, "--trace")) {
            if (index + 1 >= args.len) return error.MissingTracePath;
            index += 1;
            policy.trace_path = args[index];
        } else if (std.mem.startsWith(u8, arg, "--")) {
            return error.InvalidOption;
        } else {
            target = arg;
            target_args_start = index + 1;
            break;
        }
    }

    const target_args = if (target_args_start < args.len)
        try allocator.dupe([]const u8, args[target_args_start..])
    else
        &.{};

    return .{
        .policy = policy,
        .target = target,
        .target_args = target_args,
    };
}

fn usage(exe_name: []const u8) void {
    std.debug.print(
        \\Rosette compatibility router
        \\
        \\Usage:
        \\  {s} run [options] <target|Application.app> [-- target-args...]
        \\  {s} diagnose [options] <target|Application.app>
        \\  {s} trace-path
        \\
        \\Options:
        \\  --dry-run              Print and trace the selected route without launching
        \\  --baseline-rosetta2    Force Apple Rosetta 2 for an x86_64 Mach-O slice
        \\  --prefer-intel         Use an x86_64 slice from a universal Mach-O/app
        \\  --no-fallback          Do not fall back to Apple Rosetta 2
        \\  --allow-fallback       Allow Apple Rosetta 2 fallback for this invocation
        \\  --strict               Require Rosette ownership; abort on fallback/unsupported routes
        \\  --abort-on-fallback    Abort if a route selects Apple Rosetta 2
        \\  --abort-on-unsupported Abort if Rosette cannot launch the selected target
        \\  --trace <path>         Write the compatibility trace to a specific file
        \\  --trace-off            Disable route trace writes for this invocation
        \\
        \\Environment:
        \\  ROSETTE_ELF_PROCESSOR  Override elf_processor path
        \\  ROSETTE_EXE_RUNNER     Override rosette_exe_runner path
        \\  ROSETTE_COMPAT_TRACE   Override default handoff trace path
        \\  ROSETTE_COMPAT_STRICT  Same policy as --strict when set to 1/true/on
        \\
    , .{ exe_name, exe_name, exe_name });
}

test "parse target after options" {
    const args = [_][]const u8{ "--dry-run", "--prefer-intel", "Xenia.app", "--", "--gpu", "vulkan" };
    const parsed = try parseRouteArgs(std.testing.allocator, .{}, &args);
    defer std.testing.allocator.free(parsed.target_args);
    try std.testing.expect(parsed.policy.dry_run);
    try std.testing.expect(parsed.policy.prefer_intel_slice);
    try std.testing.expectEqualStrings("Xenia.app", parsed.target.?);
    try std.testing.expectEqual(@as(usize, 2), parsed.target_args.len);
}

test "parse strict route policy" {
    const args = [_][]const u8{ "--strict", "Xenia.app", "--gpu" };
    const parsed = try parseRouteArgs(std.testing.allocator, .{}, &args);
    defer std.testing.allocator.free(parsed.target_args);
    try std.testing.expect(parsed.policy.strict_rosette);
    try std.testing.expect(!parsed.policy.allow_rosetta2_fallback);
    try std.testing.expect(parsed.policy.abort_on_fallback);
    try std.testing.expect(parsed.policy.abort_on_unsupported);
    try std.testing.expectEqual(@as(usize, 1), parsed.target_args.len);
}
