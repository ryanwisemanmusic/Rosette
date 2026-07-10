const std = @import("std");
const classifier = @import("classifier.zig");
const process_guard = @import("entrypoint_kernel_process_guard");
const trace = @import("trace.zig");
const types = @import("types.zig");
const exit_diagnostics = @import("exit_diagnostics");

const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("sys/stat.h");
    @cInclude("unistd.h");
});

pub const Policy = struct {
    prefer_rosette: bool = true,
    allow_rosetta2_fallback: bool = false,
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
    const trace_path = policy.trace_path orelse try trace.defaultTracePath(allocator);
    var effective_policy = policy;
    if (effective_policy.trace_path == null) effective_policy.trace_path = trace_path;
    const plan = try buildPlan(init, allocator, class, target_args, effective_policy);
    if (policy.trace_enabled) {
        trace.appendDecision(allocator, trace_path, class, plan.decision, plan.argv) catch |err| {
            std.debug.print("rosette-router: warning: trace write failed: {s}\n", .{@errorName(err)});
        };
    }

    printPlan(allocator, class, plan, if (effective_policy.trace_enabled) trace_path else null);
    if (policy.dry_run) return 0;
    if (shouldAbortRoute(effective_policy, plan.decision)) abortRoute(plan.decision);
    if (plan.decision.backend == .unsupported) return 126;

    const exit_code = try runArgv(init.io, plan.argv, plan.cwd, plan.decision.backend.label());
    if (try fallbackAfterRosetteMachOFailure(init, allocator, class, target_args, effective_policy, plan.decision, exit_code, trace_path)) |fallback_code| {
        return fallback_code;
    }
    return exit_code;
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
    printPlan(allocator, class, plan, policy.trace_path);
}

pub fn buildPlan(
    init: std.process.Init,
    allocator: std.mem.Allocator,
    class: types.Classification,
    target_args: []const []const u8,
    policy: Policy,
) !RunPlan {
    var decision = try chooseDecision(allocator, class, target_args, policy);
    if (decision.backend == .unsupported) {
        if (try scriptHandoffDetail(allocator, class, target_args, policy)) |detail| {
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
            try argv.append(allocator, "/usr/bin/env");
            if (resolveAvxShim(allocator)) |shim| {
                try appendEnv(&argv, allocator, "DYLD_INSERT_LIBRARIES", shim);
            } else {
                try argv.append(allocator, "-u");
                try argv.append(allocator, "DYLD_INSERT_LIBRARIES");
            }
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
            const tool = try resolveTool(init, allocator, "ROSETTE_MACHO_PROCESSOR", "macho_processor");
            if (tool) |path| {
                try argv.append(allocator, path);
                try argv.append(allocator, class.executable_path);
                for (target_args) |arg| try argv.append(allocator, arg);
            } else {
                return unsupportedPlan(allocator, .rosette_tool_missing, "macho_processor could not be located");
            }
        },
        .rosette_script => {
            const shim_path = try ensureScriptShim(allocator, policy);
            try argv.append(allocator, "/usr/bin/env");
            const router_path = std.process.executablePathAlloc(init.io, allocator) catch "";
            try appendEnv(&argv, allocator, "ROSETTE_SCRIPT_HANDOFF_ACTIVE", "1");
            try appendEnv(&argv, allocator, "ROSETTE_VIRTUAL_UNAME_M", "x86_64");
            try appendEnv(&argv, allocator, "ROSETTE_VIRTUAL_LONG_BIT", "64");
            try appendEnv(&argv, allocator, "ROSETTE_VIRTUAL_PROC_TRANSLATED", "1");
            try appendEnv(&argv, allocator, "ROSETTE_MACHO_STRICT", "1");
            try appendEnv(&argv, allocator, "ROSETTE_SCRIPT_ALLOW_FALLBACK", if (allowsFallbackAfterRosetteFailure(policy)) "1" else "0");
            if (getenvSlice("ROSETTE_ROUTE_ROOT")) |root| try appendEnv(&argv, allocator, "ROSETTE_ROUTE_ROOT", root);
            if (getenvSlice("ROSETTE_TRACE_ROOT")) |root| try appendEnv(&argv, allocator, "ROSETTE_TRACE_ROOT", root);
            if (router_path.len != 0) try appendEnv(&argv, allocator, "ROSETTE_ROUTER", router_path);
            try appendEnv(&argv, allocator, "BASH_ENV", shim_path);
            if (getenvSlice("BASH_ENV")) |previous| try appendEnv(&argv, allocator, "ROSETTE_SCRIPT_HANDOFF_PREV_BASH_ENV", previous);
            if (policy.trace_path) |path| try appendEnv(&argv, allocator, "ROSETTE_COMPAT_TRACE", path);
            if (resolveDylib(allocator)) |dylib| {
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

fn chooseDecision(
    allocator: std.mem.Allocator,
    class: types.Classification,
    target_args: []const []const u8,
    policy: Policy,
) !types.Decision {
    if (try scriptHandoffDecision(allocator, class, target_args, policy)) |script_decision| {
        return script_decision;
    }
    return decide(class, policy);
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

fn fallbackAfterRosetteMachOFailure(
    init: std.process.Init,
    allocator: std.mem.Allocator,
    class: types.Classification,
    target_args: []const []const u8,
    policy: Policy,
    decision: types.Decision,
    exit_code: u8,
    trace_path: []const u8,
) !?u8 {
    if (exit_code == 0) return null;
    if (decision.backend != .rosette_macho) return null;
    if (!isMachOProcessorFailureStatus(exit_code)) {
        std.debug.print(
            "rosette-router: authoritative guest exit from Rosette Mach-O backend: status={d}; Apple fallback suppressed\n",
            .{exit_code},
        );
        return null;
    }
    if (!allowsFallbackAfterRosetteFailure(policy)) return null;

    std.debug.print("rosette-router: \x1b[33mEXIT BROADCAST\x1b[0m backend={s} exit_code={d}\n", .{ @tagName(decision.backend), exit_code });
    std.debug.print("rosette-router: {s}\n", .{decision.detail});

    const fallback_plan = try appleRosetta2FallbackPlan(allocator, class, target_args, exit_code);
    if (policy.trace_enabled) {
        trace.appendDecision(allocator, trace_path, class, fallback_plan.decision, fallback_plan.argv) catch |err| {
            std.debug.print("rosette-router: warning: fallback trace write failed: {s}\n", .{@errorName(err)});
        };
    }
    printPlan(allocator, class, fallback_plan, if (policy.trace_enabled) trace_path else null);
    if (shouldAbortRoute(policy, fallback_plan.decision)) abortRoute(fallback_plan.decision);
    return try runArgv(init.io, fallback_plan.argv, fallback_plan.cwd, fallback_plan.decision.backend.label());
}

fn isMachOProcessorFailureStatus(exit_code: u8) bool {
    return exit_code == 124 or exit_code == 125 or exit_code == 127;
}

fn allowsFallbackAfterRosetteFailure(policy: Policy) bool {
    return policy.allow_rosetta2_fallback and
        !policy.strict_rosette and
        !policy.abort_on_fallback and
        !policy.abort_on_unsupported;
}

fn appleRosetta2FallbackPlan(
    allocator: std.mem.Allocator,
    class: types.Classification,
    target_args: []const []const u8,
    exit_code: u8,
) !RunPlan {
    var argv: std.ArrayList([]const u8) = .empty;
    errdefer argv.deinit(allocator);

    try argv.append(allocator, "/usr/bin/env");
    if (resolveAvxShim(allocator)) |shim| {
        try appendEnv(&argv, allocator, "DYLD_INSERT_LIBRARIES", shim);
    } else {
        try argv.append(allocator, "-u");
        try argv.append(allocator, "DYLD_INSERT_LIBRARIES");
    }
    try argv.append(allocator, "/usr/bin/arch");
    try argv.append(allocator, "-x86_64");
    try argv.append(allocator, class.executable_path);
    for (target_args) |arg| try argv.append(allocator, arg);

    return .{
        .decision = .{
            .backend = .apple_rosetta2,
            .reason = if (exit_code == 125) .macho_runtime_incomplete else .rosette_backend_pending,
            .detail = if (exit_code == 125)
                try allocator.dupe(u8, "Rosette Mach-O execution stopped on an unsupported runtime capability; inspect the preceding attribution diagnostics before fallback")
            else
                try std.fmt.allocPrint(
                    allocator,
                    "Rosette Mach-O backend exited with status {d}; falling back to Apple Rosetta 2",
                    .{exit_code},
                ),
        },
        .argv = try argv.toOwnedSlice(allocator),
        .cwd = if (class.target_kind == .app_bundle) std.fs.path.dirname(class.executable_path) else null,
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
        return .{
            .backend = .rosette_macho,
            .reason = .none,
            .detail = "x86_64 Mach-O handled by Rosette Mach-O processor",
        };
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
    if (!isScriptHandoff(class, target_args, policy)) return null;
    const script = routedScriptArgument(target_args) orelse return null;
    const detail = try std.fmt.allocPrint(
        allocator,
        "x86_64 script handoff requested via {s} for {s}; running the shell natively under Rosette's diagnostic shim so launched x86_64 Mach-O programs are routed back into Rosette.",
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
        "x86_64 script handoff requested via {s} for {s}; Rosette intercepted the handoff but strict script routing is disabled.",
        .{ std.fs.path.basename(class.executable_path), script },
    );
    return detail;
}

fn isScriptHandoff(class: types.Classification, target_args: []const []const u8, policy: Policy) bool {
    if (!policy.prefer_intel_slice) return false;
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
    \\  printf 'rosette-script: intercepted x86_64 Mach-O launch: %s\n' "$__rosette_target" >&2
    \\  if [ -n "${ROSETTE_ROUTER:-}" ] && [ -x "$ROSETTE_ROUTER" ]; then
    \\    local __rosette_fallback_arg="--no-fallback"
    \\    if [ "${ROSETTE_SCRIPT_ALLOW_FALLBACK:-0}" = "1" ]; then
    \\      __rosette_fallback_arg="--allow-fallback"
    \\    fi
    \\    if [ -n "${ROSETTE_COMPAT_TRACE:-}" ]; then
    \\      ROSETTE_COMPAT_STRICT=0 ROSETTE_COMPAT_ABORT_ON_FALLBACK=0 ROSETTE_COMPAT_ABORT_ON_UNSUPPORTED=0 "$ROSETTE_ROUTER" run --prefer-intel "$__rosette_fallback_arg" --trace "$ROSETTE_COMPAT_TRACE" -- "$__rosette_target" "$@"
    \\    else
    \\      ROSETTE_COMPAT_STRICT=0 ROSETTE_COMPAT_ABORT_ON_FALLBACK=0 ROSETTE_COMPAT_ABORT_ON_UNSUPPORTED=0 "$ROSETTE_ROUTER" run --prefer-intel "$__rosette_fallback_arg" -- "$__rosette_target" "$@"
    \\    fi
    \\    local __rosette_status=$?
    \\    if [ "$__rosette_status" -ne 0 ]; then
    \\      return "$__rosette_status"
    \\    fi
    \\    return 0
    \\  fi
    \\  printf 'rosette-script: blocked x86_64 Mach-O launch without Apple Rosetta 2 fallback: %s\n' "$__rosette_target" >&2
    \\  printf 'rosette-script: Mach-O x86_64 execution backend is not implemented yet.\n' >&2
    \\  return 126
    \\}
    \\
    \\__rosette_path_can_be_function_name() {
    \\  case "$1" in
    \\    *" "*|*"'"*|"") return 1 ;;
    \\    */*) return 0 ;;
    \\    *) return 1 ;;
    \\  esac
    \\}
    \\
    \\__rosette_install_macho_blocker_for() {
    \\  local __rosette_target="$1"
    \\  [ -x "$__rosette_target" ] || return 0
    \\  __rosette_path_can_be_function_name "$__rosette_target" || return 0
    \\  eval "function $__rosette_target() { __rosette_block_macho_launch '$__rosette_target' \"\$@\"; }"
    \\}
    \\
    \\__rosette_install_macho_blockers() {
    \\  __rosette_install_macho_blocker_for "./xenia_canary.app/Contents/MacOS/xenia_canary"
    \\  if [ -n "${XENIA_BIN:-}" ]; then
    \\    __rosette_install_macho_blocker_for "$XENIA_BIN"
    \\  fi
    \\  if [ -n "${BUILD_DIR:-}" ]; then
    \\    __rosette_install_macho_blocker_for "$BUILD_DIR/xenia_canary.app/Contents/MacOS/xenia_canary"
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

fn resolveAvxShim(allocator: std.mem.Allocator) ?[]const u8 {
    if (getenvSlice("ROSETTE_AVX_SHIM")) |path| {
        if (canExecuteOrExists(allocator, path)) return allocator.dupe(u8, path) catch null;
    }
    if (getenvSlice("HOME")) |home| {
        const installed = std.fs.path.join(allocator, &.{ home, ".rosette", "lib", "avx-shim.dylib" }) catch return null;
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

fn runArgv(io: std.Io, argv: []const []const u8, cwd: ?[]const u8, label: []const u8) !u8 {
    return process_guard.runExitCode(io, .{
        .argv = argv,
        .cwd = cwd,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
        .label = label,
        .timeout_ms = process_guard.timeoutFromEnv(null),
    }) catch |err| {
        if (argv.len > 0) {
            std.debug.print("rosette-router: guarded spawn failed for {s}: {s}\n", .{ argv[0], @errorName(err) });
        } else {
            std.debug.print("rosette-router: guarded spawn failed: {s}\n", .{@errorName(err)});
        }
        return 127;
    };
}

fn printPlan(allocator: std.mem.Allocator, class: types.Classification, plan: RunPlan, trace_path: ?[]const u8) void {
    std.debug.print("Rosette compatibility route\n", .{});
    std.debug.print("  target: {s}\n", .{class.requested_path});
    std.debug.print("  executable: {s}\n", .{class.executable_path});
    std.debug.print("  guest: {s}/{s}\n", .{ class.format.label(), class.arch.label() });
    std.debug.print("  backend: {s}\n", .{plan.decision.backend.label()});
    std.debug.print("  reason: {s}\n", .{plan.decision.reason.label()});
    std.debug.print("  detail: {s}\n", .{plan.decision.detail});
    if (trace_path) |path| {
        std.debug.print("  trace: {s}\n", .{path});
        if (fileUrl(allocator, path)) |url| std.debug.print("  trace-url: {s}\n", .{url});
    }
    std.debug.print("  command:", .{});
    for (plan.argv) |arg| std.debug.print(" {s}", .{arg});
    std.debug.print("\n", .{});
}

fn fileUrl(allocator: std.mem.Allocator, path: []const u8) ?[]const u8 {
    if (path.len == 0 or path[0] != '/') return null;
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    out.appendSlice(allocator, "file://") catch return null;
    for (path) |ch| {
        switch (ch) {
            ' ' => out.appendSlice(allocator, "%20") catch return null,
            '"' => out.appendSlice(allocator, "%22") catch return null,
            '#' => out.appendSlice(allocator, "%23") catch return null,
            '%' => out.appendSlice(allocator, "%25") catch return null,
            '<' => out.appendSlice(allocator, "%3C") catch return null,
            '>' => out.appendSlice(allocator, "%3E") catch return null,
            '?' => out.appendSlice(allocator, "%3F") catch return null,
            '[' => out.appendSlice(allocator, "%5B") catch return null,
            '\\' => out.appendSlice(allocator, "%5C") catch return null,
            ']' => out.appendSlice(allocator, "%5D") catch return null,
            '^' => out.appendSlice(allocator, "%5E") catch return null,
            '`' => out.appendSlice(allocator, "%60") catch return null,
            '{' => out.appendSlice(allocator, "%7B") catch return null,
            '|' => out.appendSlice(allocator, "%7C") catch return null,
            '}' => out.appendSlice(allocator, "%7D") catch return null,
            else => out.append(allocator, ch) catch return null,
        }
    }
    return out.toOwnedSlice(allocator) catch null;
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

test "x86_64 Mach-O routes to Rosette Mach-O processor by default" {
    const class = types.Classification{
        .target_kind = .file,
        .format = .mach_o,
        .arch = .x86_64,
        .requested_path = "Xenia",
        .executable_path = "Xenia",
        .has_x86_64 = true,
    };
    const decision = decide(class, .{});
    try std.testing.expectEqual(types.Backend.rosette_macho, decision.backend);
    try std.testing.expectEqual(types.FallbackReason.none, decision.reason);
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
    try std.testing.expectEqual(types.Backend.rosette_macho, decide(class, .{ .prefer_intel_slice = true }).backend);
    try std.testing.expectEqual(types.Backend.rosette_macho, decide(class, .{ .prefer_intel_slice = true, .allow_rosetta2_fallback = false, .strict_rosette = true }).backend);
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

test "strict bash script handoff overrides Mach-O processor route" {
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
    const decision = try chooseDecision(std.testing.allocator, class, &args, .{
        .prefer_intel_slice = true,
        .allow_rosetta2_fallback = false,
        .strict_rosette = true,
    });
    defer std.testing.allocator.free(decision.detail);
    try std.testing.expectEqual(types.Backend.rosette_script, decision.backend);
    try std.testing.expectEqual(types.FallbackReason.script_handoff_requires_macho, decision.reason);
}

test "non-strict bash script handoff still selects script backend" {
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
    const decision = try chooseDecision(std.testing.allocator, class, &args, .{
        .prefer_intel_slice = true,
        .allow_rosetta2_fallback = true,
    });
    defer std.testing.allocator.free(decision.detail);
    try std.testing.expectEqual(types.Backend.rosette_script, decision.backend);
}

test "Apple Rosetta fallback plan strips or overrides DYLD interposer" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const class = types.Classification{
        .target_kind = .file,
        .format = .mach_o,
        .arch = .x86_64,
        .requested_path = "xenia_canary",
        .executable_path = "./xenia_canary.app/Contents/MacOS/xenia_canary",
        .has_x86_64 = true,
    };
    const args = [_][]const u8{"--gpu=vulkan"};
    const plan = try appleRosetta2FallbackPlan(allocator, class, &args, 2);
    try std.testing.expectEqual(types.Backend.apple_rosetta2, plan.decision.backend);
    try std.testing.expectEqualStrings("/usr/bin/env", plan.argv[0]);
    // Find /usr/bin/arch index regardless of DYLD_INSERT_LIBRARIES setup
    const arch_idx = for (plan.argv, 0..) |arg, i| {
        if (std.mem.eql(u8, arg, "/usr/bin/arch")) break i;
    } else @panic("expected /usr/bin/arch in argv");
    try std.testing.expectEqualStrings("-x86_64", plan.argv[arch_idx + 1]);
    try std.testing.expectEqualStrings(class.executable_path, plan.argv[arch_idx + 2]);
    try std.testing.expectEqualStrings(args[0], plan.argv[arch_idx + 3]);
    // Between plan.argv[0] (env) and arch_idx, either -u DYLD_INSERT_LIBRARIES
    // (strip) or DYLD_INSERT_LIBRARIES=<path> (override) must appear
    try std.testing.expect(std.mem.startsWith(u8, plan.argv[arch_idx - 1], "DYLD_INSERT_LIBRARIES") or
        (std.mem.eql(u8, plan.argv[arch_idx - 2], "-u") and
            std.mem.eql(u8, plan.argv[arch_idx - 1], "DYLD_INSERT_LIBRARIES")));
}

test "Mach-O status 125 identifies an incomplete runtime without guessing the cause" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const class = types.Classification{
        .target_kind = .file,
        .format = .mach_o,
        .arch = .x86_64,
        .requested_path = "xenia_canary",
        .executable_path = "xenia_canary",
        .has_x86_64 = true,
    };
    const plan = try appleRosetta2FallbackPlan(allocator, class, &.{}, 125);
    try std.testing.expectEqual(types.FallbackReason.macho_runtime_incomplete, plan.decision.reason);
    try std.testing.expect(std.mem.indexOf(u8, plan.decision.detail, "unsupported runtime capability") != null);
}

test "Mach-O guest exits are not mistaken for processor failures" {
    try std.testing.expect(!isMachOProcessorFailureStatus(1));
    try std.testing.expect(!isMachOProcessorFailureStatus(2));
    try std.testing.expect(isMachOProcessorFailureStatus(124));
    try std.testing.expect(isMachOProcessorFailureStatus(125));
    try std.testing.expect(isMachOProcessorFailureStatus(127));
}

test "script shim passes target separator before target args" {
    try std.testing.expect(std.mem.indexOf(u8, script_handoff_shim, "-- \"$__rosette_target\" \"$@\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, script_handoff_shim, "\"$__rosette_target\" -- \"$@\"") == null);
    try std.testing.expect(std.mem.indexOf(u8, script_handoff_shim, "return 0") != null);
}

test "file URL escapes spaces in trace paths" {
    const url = fileUrl(std.testing.allocator, "/tmp/Rosetta 3/.rosette/trace.log").?;
    defer std.testing.allocator.free(url);
    try std.testing.expectEqualStrings("file:///tmp/Rosetta%203/.rosette/trace.log", url);
}
