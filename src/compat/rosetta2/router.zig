const std = @import("std");
const classifier = @import("classifier.zig");
const trace = @import("trace.zig");
const types = @import("types.zig");

const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("sys/stat.h");
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
    var decision = decide(class, policy);
    if (decision.backend == .unsupported) {
        if (try scriptHandoffDecision(allocator, class, target_args, policy)) |script_decision| {
            decision = script_decision;
        } else if (try scriptHandoffDetail(allocator, class, target_args, policy)) |detail| {
            decision = .{
                .backend = .unsupported,
                .reason = .script_handoff_requires_macho,
                .detail = detail,
            };
        }
    }

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
        .rosette_script => {
            const shim_path = try ensureScriptShim(allocator, policy);
            try argv.append(allocator, "/usr/bin/env");
            try appendEnv(&argv, allocator, "ROSETTE_SCRIPT_HANDOFF_ACTIVE", "1");
            try appendEnv(&argv, allocator, "ROSETTE_VIRTUAL_UNAME_M", "x86_64");
            try appendEnv(&argv, allocator, "ROSETTE_VIRTUAL_LONG_BIT", "64");
            try appendEnv(&argv, allocator, "ROSETTE_VIRTUAL_PROC_TRANSLATED", "1");
            try appendEnv(&argv, allocator, "BASH_ENV", shim_path);
            if (getenvSlice("BASH_ENV")) |previous| try appendEnv(&argv, allocator, "ROSETTE_SCRIPT_HANDOFF_PREV_BASH_ENV", previous);
            if (policy.trace_path) |path| try appendEnv(&argv, allocator, "ROSETTE_COMPAT_TRACE", path);
            if (resolveDylib(allocator)) |dylib| {
                try appendEnv(&argv, allocator, "ROSETTE_MACHO_STRICT", "1");
                if (getenvSlice("DYLD_INSERT_LIBRARIES")) |existing| {
                    const joined = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ dylib, existing });
                    try appendEnv(&argv, allocator, "DYLD_INSERT_LIBRARIES", joined);
                } else {
                    try appendEnv(&argv, allocator, "DYLD_INSERT_LIBRARIES", dylib);
                }
            }
            try argv.append(allocator, class.executable_path);
            for (target_args) |arg| try argv.append(allocator, arg);
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

fn scriptHandoffDecision(
    allocator: std.mem.Allocator,
    class: types.Classification,
    target_args: []const []const u8,
    policy: Policy,
) !?types.Decision {
    if (!policy.strict_rosette and !policy.abort_on_unsupported) return null;
    if (!isScriptHandoff(class, target_args, policy)) return null;
    const script = routedScriptArgument(target_args) orelse return null;
    const detail = try std.fmt.allocPrint(
        allocator,
        "x86_64 script handoff requested via {s} for {s}; running the script under Rosette's diagnostic shell shim. x86_64 Mach-O process launches remain blocked/traced until Rosette's Mach-O backend exists.",
        .{ std.fs.path.basename(class.executable_path), script },
    );
    return .{
        .backend = .rosette_script,
        .reason = .script_handoff_requires_macho,
        .detail = detail,
    };
}

fn scriptHandoffDetail(
    allocator: std.mem.Allocator,
    class: types.Classification,
    target_args: []const []const u8,
    policy: Policy,
) !?[]const u8 {
    if (!isScriptHandoff(class, target_args, policy)) return null;

    const script = routedScriptArgument(target_args) orelse return null;
    const detail = try std.fmt.allocPrint(
        allocator,
        "x86_64 script handoff requested via {s} for {s}; Rosette intercepted the handoff, but the Mach-O x86_64 process backend needed to run this shell/script is not implemented yet. Apple Rosetta 2 fallback is disabled by strict policy.",
        .{ std.fs.path.basename(class.executable_path), script },
    );
    return detail;
}

fn isScriptHandoff(class: types.Classification, target_args: []const []const u8, policy: Policy) bool {
    if (!policy.prefer_intel_slice) return false;
    if (policy.allow_rosetta2_fallback and !policy.strict_rosette and !policy.abort_on_unsupported) return false;
    if (class.format != .mach_o or !class.has_x86_64) return false;
    if (!isShellExecutable(class.executable_path)) return false;
    return routedScriptArgument(target_args) != null;
}

fn routedScriptArgument(args: []const []const u8) ?[]const u8 {
    if (args.len == 0) return null;
    if (std.mem.eql(u8, args[0], "-c")) {
        if (args.len >= 2) return "bash -c inline command";
        return null;
    }
    if (std.mem.eql(u8, args[0], "--")) {
        if (args.len >= 2) return args[1];
        return null;
    }
    if (std.mem.startsWith(u8, args[0], "-")) return null;
    return args[0];
}

fn isShellExecutable(path: []const u8) bool {
    const base = std.fs.path.basename(path);
    return std.mem.eql(u8, base, "bash") or
        std.mem.eql(u8, base, "sh") or
        std.mem.eql(u8, base, "zsh");
}

fn appendEnv(argv: *std.ArrayList([]const u8), allocator: std.mem.Allocator, key: []const u8, value: []const u8) !void {
    try argv.append(allocator, try std.fmt.allocPrint(allocator, "{s}={s}", .{ key, value }));
}

fn ensureScriptShim(allocator: std.mem.Allocator, policy: Policy) ![]const u8 {
    const base = if (policy.trace_path) |path|
        std.fs.path.dirname(path) orelse "/tmp"
    else if (getenvSlice("HOME")) |home|
        try std.fs.path.join(allocator, &.{ home, ".rosette", "logs" })
    else
        "/tmp";
    try makePathRecursive(allocator, base);
    const shim_path = try std.fs.path.join(allocator, &.{ base, "rosette-script-handoff.bashenv" });
    try writeFilePath(allocator, shim_path, script_handoff_shim);
    _ = chmodPath(allocator, shim_path, 0o644) catch {};
    return shim_path;
}

const script_handoff_shim =
    \\# Rosette x86_64 script handoff shim. Generated by rosette-router.
    \\if [ -n "${ROSETTE_SCRIPT_HANDOFF_PREV_BASH_ENV:-}" ] && [ -f "$ROSETTE_SCRIPT_HANDOFF_PREV_BASH_ENV" ]; then
    \\  . "$ROSETTE_SCRIPT_HANDOFF_PREV_BASH_ENV"
    \\fi
    \\
    \\__rosette_script_trace() {
    \\  if [ -n "${ROSETTE_COMPAT_TRACE:-}" ]; then
    \\    {
    \\      printf '# Rosette script handoff\n'
    \\      printf 'event = "%s"\n' "$1"
    \\      printf 'cwd = "%s"\n' "$PWD"
    \\      printf '\n'
    \\    } >> "$ROSETTE_COMPAT_TRACE" 2>/dev/null || true
    \\  fi
    \\}
    \\
    \\uname() {
    \\  if [ "$#" -eq 1 ] && [ "$1" = "-m" ]; then
    \\    printf '%s\n' "${ROSETTE_VIRTUAL_UNAME_M:-x86_64}"
    \\    return 0
    \\  fi
    \\  command uname "$@"
    \\}
    \\
    \\arch() {
    \\  if [ "$#" -eq 0 ]; then
    \\    printf '%s\n' "${ROSETTE_VIRTUAL_UNAME_M:-x86_64}"
    \\    return 0
    \\  fi
    \\  command /usr/bin/arch "$@"
    \\}
    \\
    \\getconf() {
    \\  if [ "$#" -eq 1 ] && [ "$1" = "LONG_BIT" ]; then
    \\    printf '%s\n' "${ROSETTE_VIRTUAL_LONG_BIT:-64}"
    \\    return 0
    \\  fi
    \\  command getconf "$@"
    \\}
    \\
    \\sysctl() {
    \\  if [ "$#" -ge 2 ] && [ "$1" = "-in" ] && [ "$2" = "sysctl.proc_translated" ]; then
    \\    printf '%s\n' "${ROSETTE_VIRTUAL_PROC_TRANSLATED:-1}"
    \\    return 0
    \\  fi
    \\  command sysctl "$@"
    \\}
    \\
    \\__rosette_block_macho_launch() {
    \\  local __rosette_target="$1"
    \\  shift || true
    \\  __rosette_script_trace "blocked_x86_64_macho target=$__rosette_target"
    \\  printf 'rosette-script: blocked x86_64 Mach-O launch without Apple Rosetta 2 fallback: %s\n' "$__rosette_target" >&2
    \\  printf 'rosette-script: Mach-O x86_64 execution backend is not implemented yet.\n' >&2
    \\  return 126
    \\}
    \\
    \\__rosette_install_macho_blockers() {
    \\  if [ -x ./xenia_canary.app/Contents/MacOS/xenia_canary ]; then
    \\    eval 'function ./xenia_canary.app/Contents/MacOS/xenia_canary() { __rosette_block_macho_launch "./xenia_canary.app/Contents/MacOS/xenia_canary" "$@"; }'
    \\  fi
    \\}
    \\
    \\trap '__rosette_install_macho_blockers' DEBUG
    \\__rosette_install_macho_blockers
    \\__rosette_script_trace "entered_native_script_handoff"
    \\
;

fn resolveDylib(allocator: std.mem.Allocator) ?[]const u8 {
    if (getenvSlice("ROSETTE_DYLD_INTERPOSER")) |path| {
        if (canExecuteOrExists(allocator, path)) return allocator.dupe(u8, path) catch null;
    }
    if (getenvSlice("HOME")) |home| {
        const installed = std.fs.path.join(allocator, &.{ home, ".rosette", "lib", "rosette-exec.dylib" }) catch return null;
        if (canExecuteOrExists(allocator, installed)) return installed;
    }
    return null;
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

fn canExecuteOrExists(allocator: std.mem.Allocator, path: []const u8) bool {
    const path_z = allocator.dupeZ(u8, path) catch return false;
    return c.access(path_z.ptr, 0) == 0;
}

fn writeFilePath(allocator: std.mem.Allocator, path: []const u8, contents: []const u8) !void {
    const path_z = try allocator.dupeZ(u8, path);
    const fp = c.fopen(path_z.ptr, "wb");
    if (fp == null) return error.FileWriteFailed;
    defer _ = c.fclose(fp);
    if (contents.len != 0 and c.fwrite(contents.ptr, 1, contents.len, fp) != contents.len) return error.FileWriteFailed;
}

fn chmodPath(allocator: std.mem.Allocator, path: []const u8, mode: u16) !void {
    const path_z = try allocator.dupeZ(u8, path);
    if (c.chmod(path_z.ptr, mode) != 0) return error.ChmodFailed;
}

fn makePathRecursive(allocator: std.mem.Allocator, raw_path: []const u8) !void {
    if (raw_path.len == 0) return;
    var current: std.ArrayList(u8) = .empty;
    defer current.deinit(allocator);

    if (raw_path[0] == '/') try current.append(allocator, '/');
    var it = std.mem.splitScalar(u8, raw_path, '/');
    while (it.next()) |part| {
        if (part.len == 0) continue;
        if (current.items.len > 1 and current.items[current.items.len - 1] != '/') try current.append(allocator, '/');
        try current.appendSlice(allocator, part);
        const path_z = try allocator.dupeZ(u8, current.items);
        if (c.mkdir(path_z.ptr, 0o755) != 0) {
            if (c.access(path_z.ptr, 0) != 0) return error.MakePathFailed;
        }
    }
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

test "strict bash script handoff selects diagnostic script backend" {
    const class = types.Classification{
        .target_kind = .file,
        .format = .mach_o,
        .arch = .universal,
        .requested_path = "/bin/bash",
        .executable_path = "/bin/bash",
        .has_arm64 = true,
        .has_x86_64 = true,
    };
    const args = [_][]const u8{"/tmp/xenia-rosetta.12345"};
    const decision = (try scriptHandoffDecision(std.testing.allocator, class, &args, .{
        .prefer_intel_slice = true,
        .allow_rosetta2_fallback = false,
        .strict_rosette = true,
    })).?;
    defer std.testing.allocator.free(decision.detail);
    try std.testing.expectEqual(types.Backend.rosette_script, decision.backend);
    try std.testing.expectEqual(types.FallbackReason.script_handoff_requires_macho, decision.reason);
    try std.testing.expect(std.mem.indexOf(u8, decision.detail, "x86_64 script handoff") != null);
    try std.testing.expect(std.mem.indexOf(u8, decision.detail, "/tmp/xenia-rosetta.12345") != null);
}
