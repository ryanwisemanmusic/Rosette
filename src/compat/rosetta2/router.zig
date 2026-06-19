const std = @import("std");
const classifier = @import("classifier.zig");
const trace = @import("trace.zig");
const types = @import("types.zig");

const c = @cImport({
    @cInclude("stdlib.h");
    @cInclude("unistd.h");
});

pub const Policy = struct {
    prefer_rosette: bool = true,
    allow_rosetta2_fallback: bool = true,
    force_apple_rosetta2: bool = false,
    prefer_intel_slice: bool = false,
    strict_rosette: bool = false,
    abort_on_fallback: bool = false,
    abort_on_unsupported: bool = false,
    trace_enabled: bool = true,
    dry_run: bool = false,
    trace_path: ?[]const u8 = null,
};

pub const RunPlan = struct {
    decision: types.Decision,
    argv: []const []const u8,
    cwd: ?[]const u8 = null,
};

pub fn runTarget(
    init: std.process.Init,
    allocator: std.mem.Allocator,
    raw_target: []const u8,
    target_args: []const []const u8,
    policy: Policy,
) !u8 {
    const class = try classifier.classifyPath(init.io, allocator, raw_target);
    const plan = try buildPlan(init, allocator, class, target_args, policy);
    const trace_path = policy.trace_path orelse try trace.defaultTracePath(allocator);
    if (policy.trace_enabled) {
        trace.appendDecision(allocator, trace_path, class, plan.decision, plan.argv) catch |err| {
            std.debug.print("rosette-router: warning: trace write failed: {s}\n", .{@errorName(err)});
        };
    }

    printPlan(class, plan, if (policy.trace_enabled) trace_path else null);
    if (policy.dry_run) return 0;
    if (shouldAbortRoute(policy, plan.decision)) abortRoute(plan.decision);
    if (plan.decision.backend == .unsupported) return 126;

    return try runArgv(init.io, plan.argv, plan.cwd);
}

pub fn diagnoseTarget(
    init: std.process.Init,
    allocator: std.mem.Allocator,
    raw_target: []const u8,
    target_args: []const []const u8,
    policy: Policy,
) !void {
    const class = try classifier.classifyPath(init.io, allocator, raw_target);
    const plan = try buildPlan(init, allocator, class, target_args, policy);
    printPlan(class, plan, policy.trace_path);
}

pub fn buildPlan(
    init: std.process.Init,
    allocator: std.mem.Allocator,
    class: types.Classification,
    target_args: []const []const u8,
    policy: Policy,
) !RunPlan {
    const decision = decide(class, policy);

    var argv: std.ArrayList([]const u8) = .empty;
    errdefer argv.deinit(allocator);
    var cwd: ?[]const u8 = null;

    switch (decision.backend) {
        .native => {
            if (class.target_kind == .app_bundle) {
                try argv.append(allocator, "/usr/bin/open");
                try argv.append(allocator, class.requested_path);
            } else {
                try argv.append(allocator, class.executable_path);
                for (target_args) |arg| try argv.append(allocator, arg);
            }
        },
        .apple_rosetta2 => {
            try argv.append(allocator, "/usr/bin/arch");
            try argv.append(allocator, "-x86_64");
            try argv.append(allocator, class.executable_path);
            for (target_args) |arg| try argv.append(allocator, arg);
            if (class.target_kind == .app_bundle) {
                cwd = std.fs.path.dirname(class.executable_path);
            }
        },
        .rosette_elf => {
            const tool = try resolveTool(init, allocator, "ROSETTE_ELF_PROCESSOR", "elf_processor");
            if (tool) |path| {
                try argv.append(allocator, path);
                try argv.append(allocator, class.executable_path);
                for (target_args) |arg| try argv.append(allocator, arg);
            } else {
                return unsupportedPlan(allocator, .rosette_tool_missing, "elf_processor could not be located");
            }
        },
        .rosette_pe => {
            const tool = try resolveTool(init, allocator, "ROSETTE_EXE_RUNNER", "rosette_exe_runner");
            if (tool) |path| {
                try argv.append(allocator, path);
                try argv.append(allocator, "--open");
                try argv.append(allocator, class.executable_path);
            } else {
                return unsupportedPlan(allocator, .rosette_tool_missing, "rosette_exe_runner could not be located");
            }
        },
        .rosette_macho => {
            return unsupportedPlan(allocator, .rosette_backend_pending, "Mach-O x86_64 execution is not implemented in Rosette yet");
        },
        .unsupported => {
            try argv.append(allocator, "unsupported");
        },
    }

    return .{
        .decision = decision,
        .argv = try argv.toOwnedSlice(allocator),
        .cwd = cwd,
    };
}

fn unsupportedPlan(allocator: std.mem.Allocator, reason: types.FallbackReason, detail: []const u8) !RunPlan {
    const argv = try allocator.alloc([]const u8, 1);
    argv[0] = "unsupported";
    return .{
        .decision = .{
            .backend = .unsupported,
            .reason = reason,
            .detail = detail,
        },
        .argv = argv,
    };
}

pub fn decide(class: types.Classification, policy: Policy) types.Decision {
    switch (class.format) {
        .elf => {
            if (class.has_x86_64) {
                return .{
                    .backend = .rosette_elf,
                    .reason = .none,
                    .detail = "x86_64 Linux ELF is handled by Rosette elf_processor",
                };
            }
            return unsupported(.unsupported_guest, "ELF machine is not supported by this router");
        },
        .pe => {
            if (class.arch == .x86 or class.arch == .x86_64) {
                return .{
                    .backend = .rosette_pe,
                    .reason = .none,
                    .detail = "Windows PE is handled by Rosette EXE intake",
                };
            }
            return unsupported(.unsupported_guest, "PE machine is not supported by this router");
        },
        .mach_o => return decideMachO(class, policy),
        .unknown => {
            if (policy.prefer_intel_slice and policy.allow_rosetta2_fallback) {
                return .{
                    .backend = .apple_rosetta2,
                    .reason = .unsupported_container,
                    .detail = "unknown or script-like target came from an x86_64 arch request; deferring to /usr/bin/arch",
                };
            }
            return unsupported(.unsupported_container, class.note);
        },
    }
}

fn decideMachO(class: types.Classification, policy: Policy) types.Decision {
    const can_use_intel = class.has_x86_64;
    const can_use_native = class.has_arm64 and !policy.prefer_intel_slice;

    if (policy.force_apple_rosetta2) {
        if (can_use_intel and policy.allow_rosetta2_fallback) {
            return .{
                .backend = .apple_rosetta2,
                .reason = .forced_baseline,
                .detail = "baseline mode requested Apple Rosetta 2",
            };
        }
        return unsupported(.apple_rosetta2_disabled, "Apple Rosetta 2 baseline was requested but no x86_64 slice is available");
    }

    if (can_use_native) {
        return .{
            .backend = .native,
            .reason = .native_arm64_available,
            .detail = "ARM64 slice is available; routing natively unless an Intel slice is explicitly requested",
        };
    }

    if (policy.prefer_rosette and can_use_intel) {
        if (policy.allow_rosetta2_fallback) {
            return .{
                .backend = .apple_rosetta2,
                .reason = .rosette_backend_pending,
                .detail = "Rosette Mach-O x86_64 backend is pending; falling back to Apple Rosetta 2 with trace",
            };
        }
        return unsupported(.apple_rosetta2_disabled, "Rosette Mach-O x86_64 backend is pending and Apple Rosetta 2 fallback is disabled");
    }

    if (can_use_intel and policy.allow_rosetta2_fallback) {
        return .{
            .backend = .apple_rosetta2,
            .reason = .none,
            .detail = "x86_64 Mach-O selected for Apple Rosetta 2 baseline",
        };
    }

    if (class.has_i386) {
        return unsupported(.rosette_backend_pending, "32-bit macOS app translation is tracked separately and is not launchable yet");
    }
    return unsupported(.unsupported_guest, "Mach-O architecture is not supported by this router");
}

fn unsupported(reason: types.FallbackReason, detail: []const u8) types.Decision {
    return .{
        .backend = .unsupported,
        .reason = reason,
        .detail = detail,
    };
}

fn shouldAbortRoute(policy: Policy, decision: types.Decision) bool {
    return switch (decision.backend) {
        .apple_rosetta2 => policy.strict_rosette or policy.abort_on_fallback,
        .unsupported => policy.strict_rosette or policy.abort_on_unsupported,
        else => false,
    };
}

fn abortRoute(decision: types.Decision) noreturn {
    std.debug.print("rosette-router: strict compatibility abort\n", .{});
    std.debug.print("  backend: {s}\n", .{decision.backend.label()});
    std.debug.print("  reason: {s}\n", .{decision.reason.label()});
    std.debug.print("  detail: {s}\n", .{decision.detail});
    c.abort();
    unreachable;
}

fn resolveTool(init: std.process.Init, allocator: std.mem.Allocator, env_name: [:0]const u8, tool_name: []const u8) !?[]const u8 {
    if (getenvSlice(env_name)) |env_path| {
        if (canExecute(allocator, env_path)) return try allocator.dupe(u8, env_path);
    }

    const self_path = std.process.executablePathAlloc(init.io, allocator) catch "";
    if (self_path.len != 0) {
        if (std.fs.path.dirname(self_path)) |self_dir| {
            const sibling = try std.fs.path.join(allocator, &.{ self_dir, tool_name });
            if (canExecute(allocator, sibling)) return sibling;
        }
    }

    if (getenvSlice("ROSETTE_SOURCE_ROOT")) |source_root| {
        const from_source = try std.fs.path.join(allocator, &.{ source_root, "zig-out", "bin", tool_name });
        if (canExecute(allocator, from_source)) return from_source;
    }

    if (getenvSlice("HOME")) |home| {
        const installed = try std.fs.path.join(allocator, &.{ home, ".rosette", "bin", tool_name });
        if (canExecute(allocator, installed)) return installed;
    }

    if (resolveOnPath(allocator, tool_name)) |path| return path;
    return null;
}

fn resolveOnPath(allocator: std.mem.Allocator, tool_name: []const u8) ?[]const u8 {
    const path = getenvSlice("PATH") orelse return null;
    var it = std.mem.splitScalar(u8, path, ':');
    while (it.next()) |dir| {
        if (dir.len == 0) continue;
        const candidate = std.fs.path.join(allocator, &.{ dir, tool_name }) catch continue;
        if (canExecute(allocator, candidate)) return candidate;
    }
    return null;
}

fn runArgv(io: std.Io, argv: []const []const u8, cwd: ?[]const u8) !u8 {
    const child = if (cwd) |dir|
        std.process.spawn(io, .{
            .argv = argv,
            .cwd = .{ .path = dir },
            .stdin = .inherit,
            .stdout = .inherit,
            .stderr = .inherit,
        })
    else
        std.process.spawn(io, .{
            .argv = argv,
            .stdin = .inherit,
            .stdout = .inherit,
            .stderr = .inherit,
        });

    var process = child catch |err| {
        std.debug.print("rosette-router: failed to spawn {s}: {s}\n", .{ argv[0], @errorName(err) });
        return 127;
    };
    const term = process.wait(io) catch |err| {
        std.debug.print("rosette-router: failed waiting for {s}: {s}\n", .{ argv[0], @errorName(err) });
        return 127;
    };
    return switch (term) {
        .exited => |code| code,
        .signal => |sig| 128 + @as(u8, @intCast(@intFromEnum(sig))),
        .stopped => 128,
        .unknown => 1,
    };
}

fn printPlan(class: types.Classification, plan: RunPlan, trace_path: ?[]const u8) void {
    std.debug.print("Rosette compatibility route\n", .{});
    std.debug.print("  target: {s}\n", .{class.requested_path});
    std.debug.print("  executable: {s}\n", .{class.executable_path});
    std.debug.print("  guest: {s}/{s}\n", .{ class.format.label(), class.arch.label() });
    std.debug.print("  backend: {s}\n", .{plan.decision.backend.label()});
    std.debug.print("  reason: {s}\n", .{plan.decision.reason.label()});
    std.debug.print("  detail: {s}\n", .{plan.decision.detail});
    if (trace_path) |path| std.debug.print("  trace: {s}\n", .{path});
    std.debug.print("  command:", .{});
    for (plan.argv) |arg| std.debug.print(" {s}", .{arg});
    std.debug.print("\n", .{});
}

fn canExecute(allocator: std.mem.Allocator, path: []const u8) bool {
    const path_z = allocator.dupeZ(u8, path) catch return false;
    return c.access(path_z.ptr, 1) == 0;
}

fn getenvSlice(name: [:0]const u8) ?[]const u8 {
    const value = std.c.getenv(name) orelse return null;
    return std.mem.sliceTo(value, 0);
}

test "x86_64 Mach-O falls back to Apple Rosetta 2 while backend is pending" {
    const class = types.Classification{
        .target_kind = .file,
        .format = .mach_o,
        .arch = .x86_64,
        .requested_path = "Xenia",
        .executable_path = "Xenia",
        .has_x86_64 = true,
    };
    const decision = decide(class, .{});
    try std.testing.expectEqual(types.Backend.apple_rosetta2, decision.backend);
    try std.testing.expectEqual(types.FallbackReason.rosette_backend_pending, decision.reason);
}

test "universal Mach-O stays native unless Intel is requested" {
    const class = types.Classification{
        .target_kind = .app_bundle,
        .format = .mach_o,
        .arch = .universal,
        .requested_path = "Xenia.app",
        .executable_path = "Xenia.app/Contents/MacOS/Xenia",
        .has_arm64 = true,
        .has_x86_64 = true,
    };
    try std.testing.expectEqual(types.Backend.native, decide(class, .{}).backend);
    try std.testing.expectEqual(types.Backend.apple_rosetta2, decide(class, .{ .prefer_intel_slice = true }).backend);
    try std.testing.expectEqual(types.Backend.unsupported, decide(class, .{ .prefer_intel_slice = true, .allow_rosetta2_fallback = false, .strict_rosette = true }).backend);
}

test "strict policy marks unsupported routes as abortable" {
    const unsupported_decision = types.Decision{
        .backend = .unsupported,
        .reason = .rosette_backend_pending,
        .detail = "test",
    };
    const fallback_decision = types.Decision{
        .backend = .apple_rosetta2,
        .reason = .rosette_backend_pending,
        .detail = "test",
    };
    try std.testing.expect(shouldAbortRoute(.{ .strict_rosette = true }, unsupported_decision));
    try std.testing.expect(shouldAbortRoute(.{ .abort_on_unsupported = true }, unsupported_decision));
    try std.testing.expect(shouldAbortRoute(.{ .strict_rosette = true }, fallback_decision));
    try std.testing.expect(shouldAbortRoute(.{ .abort_on_fallback = true }, fallback_decision));
    try std.testing.expect(!shouldAbortRoute(.{}, unsupported_decision));
    try std.testing.expect(!shouldAbortRoute(.{}, fallback_decision));
}
