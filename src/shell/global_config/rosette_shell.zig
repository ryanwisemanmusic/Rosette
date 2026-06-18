const std = @import("std");
const builtin = @import("builtin");

const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("sys/stat.h");
    @cInclude("unistd.h");
});

const block_begin = "# >>> Rosette shell integration >>>";
const block_end = "# <<< Rosette shell integration <<<";
const max_text_file = 512 * 1024;
const default_config_text =
    \\# Rosette global shell configuration.
    \\# Values are TOML. The shell helper also accepts the uppercase aliases
    \\# shown below for people who think in environment-variable names.
    \\
    \\[graphics]
    \\enabled = false
    \\
    \\[elf]
    \\# "auto" enables result summaries for detected class-style YASM/ELF
    \\# assignment projects when you run `make run` or launch `./program`.
    \\# Use "on" to always request summaries for detected projects, or "off"
    \\# to leave ELF program output untouched unless the environment asks.
    \\dump_results = "auto"
    \\dump_all_results = false
    \\result_style = "student"
    \\
    \\# Optional aliases:
    \\# GRAPHICS = "OFF"
    \\# ROSETTE_ELF_DUMP_RESULTS = "AUTO"
    \\
    \\[compat]
    \\# Compatibility routing is intentionally explicit. Use:
    \\#   rosette route run --prefer-intel /path/to/Xenia.app
    \\# Apple Rosetta 2 remains a traced fallback while Rosette's Mach-O
    \\# x86_64 backend is being brought up.
    \\allow_rosetta2_fallback = true
    \\trace = true
    \\
;

const ConfigMode = enum { off, on, auto };

const ShellConfig = struct {
    graphics_enabled: bool = false,
    elf_dump_results: ConfigMode = .auto,
    elf_dump_all_results: bool = false,
};

const Detection = struct {
    detected: bool,
    score: u32,
    kind: []const u8,
    signals: []const u8,
};

const YasmInvocation = struct {
    source_path: ?[]const u8 = null,
    artifact_path: ?[]const u8 = null,
    format: []const u8 = "bin",

    fn isElf64(self: YasmInvocation) bool {
        return std.ascii.eqlIgnoreCase(self.format, "elf64");
    }
};

const CompileInvocation = struct {
    compile_only: bool = false,
    source_path: ?[]const u8 = null,
    artifact_path: ?[]const u8 = null,
};

const ProfileTarget = struct {
    path: []const u8,
    create: bool,
};

const ElfSection = struct {
    section_type: u32,
    offset: usize,
    size: usize,
    link: usize,
    entsize: usize,
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    if (args.len < 2) return usage(args[0]);

    if (isShellCommandMode(args[1])) {
        try runRecipeShell(init, allocator, args[1..]);
        return;
    }

    if (std.mem.eql(u8, args[1], "help")) {
        return usage(args[0]);
    }
    if (std.mem.eql(u8, args[1], "config")) {
        try printConfig(init.io, allocator);
        return;
    }
    if (std.mem.eql(u8, args[1], "config-path")) {
        const path = try configPath(allocator);
        std.debug.print("{s}\n", .{path});
        return;
    }
    if (std.mem.eql(u8, args[1], "install")) {
        const source_root = if (args.len >= 3) args[2] else "";
        try installOrUpdate(init, allocator, source_root);
        return;
    }
    if (std.mem.eql(u8, args[1], "update")) {
        const source_root = if (args.len >= 3) args[2] else "";
        try installOrUpdate(init, allocator, source_root);
        return;
    }
    if (std.mem.eql(u8, args[1], "uninstall")) {
        try uninstallShell(init, allocator);
        return;
    }
    if (std.mem.eql(u8, args[1], "detect")) {
        const project_dir = if (args.len >= 3) args[2] else ".";
        const resolved = try absolutePath(allocator, project_dir);
        const detection = try detectProject(init.io, allocator, resolved);
        if (detection.detected) {
            std.debug.print("detected: {s} score={d} signals={s}\n", .{ detection.kind, detection.score, detection.signals });
            std.process.exit(0);
        }
        std.debug.print("not detected: score={d} signals={s}\n", .{ detection.score, detection.signals });
        std.process.exit(1);
    }
    if (std.mem.eql(u8, args[1], "diagnose")) {
        const project_dir = if (args.len >= 3) args[2] else ".";
        const target = if (args.len >= 4) args[3] else null;
        try diagnoseShell(init, allocator, project_dir, target);
        return;
    }
    if (std.mem.eql(u8, args[1], "prepare-make")) {
        if (args.len < 4) return usage(args[0]);
        try prepareMake(init, allocator, args[2], args[3], args[4..]);
        return;
    }
    if (std.mem.eql(u8, args[1], "finish-make")) {
        if (args.len < 4) return usage(args[0]);
        try finishMake(allocator, args[2], args[3], args[4..]);
        return;
    }
    if (std.mem.eql(u8, args[1], "clean-state")) {
        try cleanState(init.io, allocator);
        return;
    }
    if (std.mem.eql(u8, args[1], "route") or std.mem.eql(u8, args[1], "compat")) {
        try runCompatRouter(init, allocator, args[2..]);
        return;
    }
    if (std.mem.eql(u8, args[1], "run-elf")) {
        if (args.len < 3) return usage(args[0]);
        try runElfTarget(init, allocator, args[2], args[3..]);
        return;
    }
    if (std.mem.eql(u8, args[1], "tool")) {
        if (args.len < 3) return usage(args[0]);
        try runTool(init, allocator, args[2], args[3..]);
        return;
    }
    if (std.mem.eql(u8, args[1], "recipe-shell")) {
        try runRecipeShell(init, allocator, args[2..]);
        return;
    }
    if (std.mem.eql(u8, args[1], "is-elf64")) {
        if (args.len < 3) return usage(args[0]);
        const resolved = try absolutePath(allocator, args[2]);
        std.process.exit(if (try isX86_64Elf(init.io, allocator, resolved)) 0 else 1);
    }

    return usage(args[0]);
}

fn usage(exe_name: []const u8) void {
    std.debug.print(
        \\Rosette global shell helper
        \\
        \\Usage:
        \\  {s} help
        \\  {s} config
        \\  {s} config-path
        \\  {s} install [source-root]
        \\  {s} update [source-root]
        \\  {s} uninstall
        \\  {s} detect [project-directory]
        \\  {s} diagnose [project-directory] [program]
        \\  {s} prepare-make <project-directory> <env-file> [make-args...]
        \\  {s} finish-make <project-directory> <status> [make-args...]
        \\  {s} clean-state
        \\  {s} route run [options] <target|Application.app> [-- target-args...]
        \\  {s} run-elf <x86-64-elf-path> [args...]
        \\  {s} tool <tool-name> [tool-args...]
        \\  {s} recipe-shell [sh-args...]
        \\  {s} is-elf64 <path>
        \\
        \\Common config at ~/.rosette/config.toml:
        \\  [elf]
        \\  dump_results = "auto"  # off | on | auto
        \\  dump_all_results = false
        \\  [graphics]
        \\  enabled = false
        \\
    , .{ exe_name, exe_name, exe_name, exe_name, exe_name, exe_name, exe_name, exe_name, exe_name, exe_name, exe_name, exe_name, exe_name, exe_name, exe_name, exe_name });
}

fn installOrUpdate(init: std.process.Init, allocator: std.mem.Allocator, source_root: []const u8) !void {
    const home = try homeDir(allocator);
    const rosette_dir = try std.fs.path.join(allocator, &.{ home, ".rosette" });
    const bin_dir = try std.fs.path.join(allocator, &.{ rosette_dir, "bin" });
    const lib_dir = try std.fs.path.join(allocator, &.{ rosette_dir, "lib" });
    const wrapper_dir = try std.fs.path.join(allocator, &.{ rosette_dir, "wrappers" });
    const helper_path = try std.fs.path.join(allocator, &.{ bin_dir, "rosette-shell" });
    const rosette_path = try std.fs.path.join(allocator, &.{ bin_dir, "rosette" });
    const shell_path = try std.fs.path.join(allocator, &.{ rosette_dir, "rosette-shell.sh" });
    const toml_path = try std.fs.path.join(allocator, &.{ rosette_dir, "config.toml" });
    const compat_router_path = try std.fs.path.join(allocator, &.{ bin_dir, "rosette-router" });

    try makePathRecursive(allocator, bin_dir);
    try makePathRecursive(allocator, wrapper_dir);
    try makePathRecursive(allocator, lib_dir);
    try copySelf(init, allocator, helper_path);
    try copySelf(init, allocator, rosette_path);
    try ensureWrappers(allocator, wrapper_dir, helper_path);
    if (!fileExists(allocator, toml_path)) {
        try writeFilePath(allocator, toml_path, default_config_text);
        try chmodPath(allocator, toml_path, 0o644);
    }

    const elf_processor_path = try std.fs.path.join(allocator, &.{ bin_dir, "elf_processor" });
    const dyld_lib_path = try std.fs.path.join(allocator, &.{ lib_dir, "rosette-exec.dylib" });
    const is_macos = comptime builtin.target.os.tag == .macos;

    if (source_root.len != 0) {
        try copyElfProcessor(init, allocator, source_root, elf_processor_path);
        try copyCompatRouter(init, allocator, source_root, compat_router_path);
        if (is_macos) try installDylib(init, allocator, source_root, dyld_lib_path);
    }

    const snippet = try buildShellSnippet(
        allocator,
        helper_path,
        if (is_macos and fileExists(allocator, dyld_lib_path)) dyld_lib_path else null,
        if (fileExists(allocator, elf_processor_path)) elf_processor_path else null,
    );
    try writeFilePath(allocator, shell_path, snippet);
    try chmodPath(allocator, shell_path, 0o644);

    const block = try buildProfileBlock(allocator);
    try installProfileBlocks(init.io, allocator, home, block);

    if (source_root.len != 0) {
        const config_path = try std.fs.path.join(allocator, &.{ rosette_dir, "source-root" });
        const source_text = try std.fmt.allocPrint(allocator, "{s}\n", .{source_root});
        try writeFilePath(allocator, config_path, source_text);
    }

    std.debug.print("Rosette shell integration installed.\n", .{});
    std.debug.print("source: {s}\n", .{shell_path});
    std.debug.print("command: {s}\n", .{rosette_path});
    if (fileExists(allocator, elf_processor_path)) {
        std.debug.print("elf_processor: {s}\n", .{elf_processor_path});
    } else {
        std.debug.print("elf_processor: missing; build/install did not copy an ELF processor\n", .{});
    }
    if (fileExists(allocator, compat_router_path)) {
        std.debug.print("compat_router: {s}\n", .{compat_router_path});
    } else {
        std.debug.print("compat_router: missing; build/install did not copy rosette-router\n", .{});
    }
    std.debug.print("current terminal reload: source ~/.rosette/rosette-shell.sh\n", .{});
    std.debug.print("diagnose from a project: rosette-diagnose-shell ./program\n", .{});
}

fn uninstallShell(init: std.process.Init, allocator: std.mem.Allocator) !void {
    const home = try homeDir(allocator);
    const rosette_dir = try std.fs.path.join(allocator, &.{ home, ".rosette" });
    const bin_dir = try std.fs.path.join(allocator, &.{ rosette_dir, "bin" });
    const lib_dir = try std.fs.path.join(allocator, &.{ rosette_dir, "lib" });
    const wrapper_dir = try std.fs.path.join(allocator, &.{ rosette_dir, "wrappers" });
    const shell_path = try std.fs.path.join(allocator, &.{ rosette_dir, "rosette-shell.sh" });
    const helper_path = try std.fs.path.join(allocator, &.{ bin_dir, "rosette-shell" });
    const rosette_path = try std.fs.path.join(allocator, &.{ bin_dir, "rosette" });
    const compat_router_path = try std.fs.path.join(allocator, &.{ bin_dir, "rosette-router" });
    const source_root = try std.fs.path.join(allocator, &.{ rosette_dir, "source-root" });
    const toml_path = try std.fs.path.join(allocator, &.{ rosette_dir, "config.toml" });
    const elf_processor_path = try std.fs.path.join(allocator, &.{ bin_dir, "elf_processor" });
    const dyld_lib_path = try std.fs.path.join(allocator, &.{ lib_dir, "rosette-exec.dylib" });

    try removeProfileBlocks(init.io, allocator, home);

    try unlinkIfExists(allocator, shell_path);
    try unlinkIfExists(allocator, source_root);
    try unlinkIfExists(allocator, toml_path);
    try unlinkIfExists(allocator, elf_processor_path);
    try unlinkIfExists(allocator, compat_router_path);
    try unlinkIfExists(allocator, dyld_lib_path);
    try removeWrappers(allocator, wrapper_dir);
    try unlinkIfExists(allocator, helper_path);
    try unlinkIfExists(allocator, rosette_path);
    rmdirIfEmpty(allocator, wrapper_dir) catch {};
    rmdirIfEmpty(allocator, bin_dir) catch {};
    rmdirIfEmpty(allocator, lib_dir) catch {};
    rmdirIfEmpty(allocator, rosette_dir) catch {};

    std.debug.print("Rosette shell integration removed.\n", .{});
}

fn prepareMake(
    init: std.process.Init,
    allocator: std.mem.Allocator,
    project_dir_raw: []const u8,
    env_path: []const u8,
    make_args: []const []const u8,
) !void {
    const project_dir = try absolutePath(allocator, project_dir_raw);
    const detection = try detectProject(init.io, allocator, project_dir);
    if (!detection.detected) std.process.exit(1);

    const home = try homeDir(allocator);
    const wrapper_dir = try std.fs.path.join(allocator, &.{ home, ".rosette", "wrappers" });
    const elf_processor_path = try resolveElfProcessorPath(allocator);

    const helper_path = try currentHelperPath(init, allocator);
    const config = try loadShellConfig(init.io, allocator);

    const trace_dir = try std.fs.path.join(allocator, &.{ project_dir, ".rosette" });
    try makePathRecursive(allocator, trace_dir);
    const trace_path = try std.fs.path.join(allocator, &.{ trace_dir, "rosette-shell.trace.log" });
    const source_root = try currentSourceRoot(init.io, allocator);
    const assembler_runner = try resolveAssemblerRunner(allocator, helper_path, source_root);

    try appendMakeStartTrace(allocator, trace_path, project_dir, detection, make_args);
    const env_text = try buildMakeEnv(
        allocator,
        project_dir,
        wrapper_dir,
        helper_path,
        trace_path,
        detection.kind,
        source_root,
        assembler_runner,
        helper_path,
        if (fileExists(allocator, elf_processor_path)) elf_processor_path else null,
        config,
        detection,
        make_args,
    );
    try writeFilePath(allocator, env_path, env_text);
    std.process.exit(0);
}

fn finishMake(allocator: std.mem.Allocator, project_dir: []const u8, status_text: []const u8, make_args: []const []const u8) !void {
    const trace_path_raw = std.c.getenv("ROSETTE_SHELL_TRACE") orelse return;
    const trace_path = std.mem.sliceTo(trace_path_raw, 0);

    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    try out.appendSlice(allocator, "finish status=");
    try out.appendSlice(allocator, status_text);
    try out.appendSlice(allocator, " cwd=");
    try out.appendSlice(allocator, project_dir);
    try out.appendSlice(allocator, " args=");
    try appendArgs(&out, allocator, make_args);
    try out.append(allocator, '\n');
    try appendFilePath(allocator, trace_path, out.items);
}

fn runTool(init: std.process.Init, allocator: std.mem.Allocator, tool_name: []const u8, tool_args: []const []const u8) !void {
    const active = std.c.getenv("ROSETTE_SHELL_ACTIVE") orelse "";
    if (!std.mem.eql(u8, std.mem.sliceTo(active, 0), "1")) {
        try execResolved(init.io, allocator, tool_name, tool_args);
    }

    if (std.mem.eql(u8, tool_name, "yasm")) {
        try appendToolTrace(allocator, tool_name, "native+rosette-yasm-validate", tool_args);
        const code = try runNativeTool(init.io, allocator, tool_name, tool_args);
        if (code != 0) std.process.exit(code);
        try validateYasmInvocation(init, allocator, tool_args);
        std.process.exit(0);
    } else if (std.mem.eql(u8, tool_name, "ld")) {
        try appendToolTrace(allocator, tool_name, "zig-cc-linux-nostdlib", tool_args);
        try execZigLd(init.io, allocator, tool_args);
    } else if (isCxxTool(tool_name)) {
        try appendToolTrace(allocator, tool_name, "zig-cxx-linux", tool_args);
        try runZigCompilerWithCompatibility(init.io, allocator, tool_name, "c++", tool_args, true);
    } else if (isCcTool(tool_name)) {
        try appendToolTrace(allocator, tool_name, "zig-cc-linux", tool_args);
        try runZigCompilerWithCompatibility(init.io, allocator, tool_name, "cc", tool_args, false);
    } else {
        try appendToolTrace(allocator, tool_name, "native", tool_args);
        try execResolved(init.io, allocator, tool_name, tool_args);
    }
}

fn runCompatRouter(init: std.process.Init, allocator: std.mem.Allocator, route_args: []const []const u8) !void {
    const router_path = try resolveCompatRouterPath(init, allocator);
    if (!canExecute(allocator, router_path)) {
        std.debug.print("rosette-shell: rosette-router is not installed; run 'make shell-update' from Rosette or reinstall Rosette.\n", .{});
        std.debug.print("  expected: {s}\n", .{router_path});
        std.process.exit(127);
    }

    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);
    try argv.append(allocator, router_path);
    if (route_args.len == 0) {
        try argv.append(allocator, "help");
    } else {
        for (route_args) |arg| try argv.append(allocator, arg);
    }

    const code = try runArgvResult(init.io, argv.items);
    std.process.exit(code);
}

fn runRecipeShell(init: std.process.Init, allocator: std.mem.Allocator, shell_args: []const []const u8) !void {
    const rewritten = if (shell_args.len >= 2 and std.mem.eql(u8, shell_args[0], "-c"))
        try rewriteRecipeCommand(init.io, allocator, shell_args[1])
    else
        null;

    const sh_path = try allocator.dupeZ(u8, "/bin/sh");
    var argv: std.ArrayList(?[*:0]const u8) = .empty;
    defer argv.deinit(allocator);
    try argv.append(allocator, sh_path.ptr);

    for (shell_args, 0..) |arg, i| {
        const selected = blk: {
            if (i == 1) {
                if (rewritten) |command| break :blk command;
            }
            break :blk arg;
        };
        const arg_z = try allocator.dupeZ(u8, selected);
        try argv.append(allocator, arg_z.ptr);
    }
    try argv.append(allocator, null);

    _ = std.c.execve(sh_path.ptr, @ptrCast(argv.items.ptr), @ptrCast(std.c.environ));
    std.debug.print("rosette-shell: failed to exec /bin/sh\n", .{});
    std.process.exit(127);
}

fn isShellCommandMode(arg: []const u8) bool {
    return arg.len >= 2 and arg[0] == '-' and std.mem.indexOfScalar(u8, arg[1..], 'c') != null;
}

fn cleanState(io: std.Io, allocator: std.mem.Allocator) !void {
    const pkill = resolveOnPath(allocator, "pkill") orelse "/usr/bin/pkill";
    const patterns = [_][]const u8{
        "rosette-shell recipe-shell",
        "rosette-shell -c",
        "rosette-shell -ec",
        "rosette-shell tool",
        "rosette-router",
        "elf_processor",
        "rosette_assembler_runner",
        "/usr/local/bin/rose",
    };

    var killed: usize = 0;
    for (patterns) |pattern| {
        const code = runArgvResult(io, &[_][]const u8{ pkill, "-KILL", "-f", pattern }) catch |err| {
            std.debug.print("rosette-shell: clean-state failed for pattern '{s}': {s}\n", .{ pattern, @errorName(err) });
            continue;
        };
        if (code == 0) {
            killed += 1;
            std.debug.print("rosette-shell: clean-state signaled pattern '{s}'\n", .{pattern});
        } else if (code != 1) {
            std.debug.print("rosette-shell: clean-state pkill status {d} for pattern '{s}'\n", .{ code, pattern });
        }
    }

    if (killed == 0) {
        std.debug.print("rosette-shell: clean-state found no matching live helpers\n", .{});
    }
}

fn diagnoseShell(init: std.process.Init, allocator: std.mem.Allocator, project_dir_raw: []const u8, target_raw: ?[]const u8) !void {
    const home = try homeDir(allocator);
    const project_dir = try absolutePath(allocator, project_dir_raw);
    const helper = try currentHelperPath(init, allocator);
    const processor = try resolveElfProcessorPath(allocator);
    const config_path = try configPath(allocator);
    const config = try loadShellConfig(init.io, allocator);
    const source_root = try currentSourceRoot(init.io, allocator);
    const detection = detectProject(init.io, allocator, project_dir) catch Detection{
        .detected = false,
        .score = 0,
        .kind = "unknown",
        .signals = "detection-error",
    };

    std.debug.print("Rosette shell diagnosis\n", .{});
    std.debug.print("  home: {s}\n", .{home});
    std.debug.print("  project: {s}\n", .{project_dir});
    std.debug.print("  helper: {s} ({s})\n", .{ helper, if (canExecute(allocator, helper)) "executable" else "missing/not executable" });
    std.debug.print("  elf_processor: {s} ({s})\n", .{ processor, if (canExecute(allocator, processor)) "executable" else "missing/not executable" });
    std.debug.print("  config: {s}\n", .{config_path});
    std.debug.print("  source_root: {s}\n", .{if (source_root.len == 0) "(unset)" else source_root});
    std.debug.print("  dump_results: {s}\n", .{configModeName(config.elf_dump_results)});
    std.debug.print("  dump_all_results: {s}\n", .{if (config.elf_dump_all_results) "true" else "false"});
    std.debug.print("  project_detected: {s} kind={s} score={d} signals={s}\n", .{
        if (detection.detected) "yes" else "no",
        detection.kind,
        detection.score,
        detection.signals,
    });
    std.debug.print("  direct_launch_eligible: {s}\n", .{
        if (detection.detected and canExecute(allocator, processor)) "yes" else "no",
    });

    if (target_raw) |raw| {
        const target = resolveAgainstProject(allocator, project_dir, raw) catch try absolutePath(allocator, raw);
        const is_elf = isX86_64Elf(init.io, allocator, target) catch false;
        const hook_name = try std.fmt.allocPrint(allocator, "./{s}", .{std.fs.path.basename(target)});
        std.debug.print("  target: {s}\n", .{target});
        std.debug.print("  target_exists: {s}\n", .{if (fileExists(allocator, target)) "yes" else "no"});
        std.debug.print("  target_executable: {s}\n", .{if (canExecute(allocator, target)) "yes" else "no"});
        std.debug.print("  target_x86_64_elf: {s}\n", .{if (is_elf) "yes" else "no"});
        std.debug.print("  expected_zsh_hook: {s}\n", .{hook_name});
    } else {
        try diagnoseProjectExecutables(init.io, allocator, project_dir);
    }

    std.debug.print("  note: if direct ./program still says exec format error in an already-open terminal, run:\n", .{});
    std.debug.print("        source ~/.rosette/rosette-shell.sh\n", .{});
}

fn diagnoseProjectExecutables(io: std.Io, allocator: std.mem.Allocator, project_dir: []const u8) !void {
    var dir = std.Io.Dir.openDirAbsolute(io, project_dir, .{ .iterate = true }) catch |err| {
        std.debug.print("  executables: cannot scan project directory ({s})\n", .{@errorName(err)});
        return;
    };
    defer dir.close(io);

    var found: usize = 0;
    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (entry.kind != .file) continue;
        const path = try std.fs.path.join(allocator, &.{ project_dir, entry.name });
        if (!canExecute(allocator, path)) continue;
        if (!(try isX86_64Elf(io, allocator, path))) continue;
        found += 1;
        std.debug.print("  executable[{d}]: ./{s} (x86-64 ELF)\n", .{ found, entry.name });
        if (found >= 12) break;
    }
    if (found == 0) {
        std.debug.print("  executables: no executable x86-64 ELF files found in project root\n", .{});
    }
}

fn runElfTarget(init: std.process.Init, allocator: std.mem.Allocator, raw_target: []const u8, target_args: []const []const u8) !void {
    const target = try absolutePath(allocator, raw_target);
    if (!(try isX86_64Elf(init.io, allocator, target))) {
        std.debug.print("rosette-shell: not an x86-64 ELF executable: {s}\n", .{raw_target});
        std.process.exit(126);
    }

    const processor = try resolveElfProcessorPath(allocator);
    if (!canExecute(allocator, processor)) {
        std.debug.print("rosette-shell: elf_processor is not installed; run 'make shell-update' from Rosette or reinstall Rosette.\n", .{});
        std.process.exit(127);
    }

    const config = try loadShellConfig(init.io, allocator);
    const project_dir = std.fs.path.dirname(target) orelse ".";
    const detection = detectProject(init.io, allocator, project_dir) catch Detection{
        .detected = false,
        .score = 0,
        .kind = "unknown",
        .signals = "none",
    };

    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);
    try argv.append(allocator, processor);
    if (getenvSlice("ROSETTE_ELF_DUMP_RESULTS") == null and
        getenvSlice("ROSETTE_ELF_DUMP_ALL") == null and
        getenvSlice("ROSETTE_ELF_DUMP_ALL_RESULTS") == null)
    {
        if (config.elf_dump_all_results) {
            try argv.append(allocator, "--dump-all-results");
        } else if (shouldEnableDirectResultDump(config, detection)) {
            try argv.append(allocator, "--dump-results");
        }
    }
    try argv.append(allocator, target);
    for (target_args) |arg| try argv.append(allocator, arg);

    std.debug.print("Running via {s}...\n", .{processor});
    _ = c.unsetenv("DYLD_INSERT_LIBRARIES");
    const code = try runArgvResult(init.io, argv.items);
    std.process.exit(code);
}

fn rewriteRecipeCommand(io: std.Io, allocator: std.mem.Allocator, command: []const u8) !?[]const u8 {
    const token = firstShellToken(command) orelse return null;
    if (token.len == 0 or std.mem.indexOfScalar(u8, token, '/') == null) return null;

    const resolved = absolutePath(allocator, token) catch return null;
    if (!(try isX86_64Elf(io, allocator, resolved))) return null;
    const processor = getenvSlice("ROSETTE_ELF_PROCESSOR") orelse return null;
    if (!canExecute(allocator, processor)) return null;

    try appendToolTrace(allocator, "recipe-shell", "elf-processor", &[_][]const u8{token});

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try appendShellQuoted(&out, allocator, processor);
    try out.append(allocator, ' ');
    try out.appendSlice(allocator, command);
    return out.items;
}

fn firstShellToken(command: []const u8) ?[]const u8 {
    var start: usize = 0;
    while (start < command.len and isShellWhitespace(command[start])) : (start += 1) {}
    if (start >= command.len) return null;

    const quote = command[start];
    if (quote == '\'' or quote == '"') {
        var end = start + 1;
        while (end < command.len and command[end] != quote) : (end += 1) {}
        if (end >= command.len) return null;
        return command[start + 1 .. end];
    }

    var end = start;
    while (end < command.len) : (end += 1) {
        const ch = command[end];
        if (isShellWhitespace(ch) or ch == '<' or ch == '>' or ch == '|' or ch == '&' or ch == ';') break;
    }
    return command[start..end];
}

fn isShellWhitespace(ch: u8) bool {
    return ch == ' ' or ch == '\t' or ch == '\r' or ch == '\n';
}

fn isX86_64Elf(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !bool {
    _ = io;
    var header: [64]u8 = undefined;
    const path_z = try allocator.dupeZ(u8, path);
    const fp = c.fopen(path_z.ptr, "rb");
    if (fp == null) return false;
    defer _ = c.fclose(fp);

    const n = c.fread(header[0..].ptr, 1, header.len, fp);
    const bytes = header[0..n];
    if (bytes.len < 20) return false;
    if (!std.mem.eql(u8, bytes[0..4], "\x7fELF")) return false;
    if (bytes[4] != 2 or bytes[5] != 1) return false;
    const e_type = std.mem.readInt(u16, bytes[16..18], .little);
    const e_machine = std.mem.readInt(u16, bytes[18..20], .little);
    return (e_type == 2 or e_type == 3) and e_machine == 62;
}

fn validateYasmInvocation(init: std.process.Init, allocator: std.mem.Allocator, tool_args: []const []const u8) !void {
    const invocation = try parseYasmInvocation(allocator, tool_args);
    if (!invocation.isElf64()) {
        try appendToolTrace(allocator, "yasm", "rosette-validate-skip-non-elf64", tool_args);
        return;
    }

    const source_path = invocation.source_path orelse {
        try appendToolTrace(allocator, "yasm", "rosette-validate-skip-no-source", tool_args);
        return;
    };
    const artifact_path = invocation.artifact_path orelse {
        try appendToolTrace(allocator, "yasm", "rosette-validate-skip-no-artifact", tool_args);
        return;
    };

    const helper_path = currentHelperPath(init, allocator) catch "";
    const source_root = currentSourceRoot(init.io, allocator) catch "";
    const runner = (try resolveAssemblerRunner(allocator, helper_path, source_root)) orelse {
        try appendToolTrace(allocator, "yasm", "rosette-validate-skip-no-runner", tool_args);
        return;
    };
    const log_path = try yasmValidationLogPath(allocator, source_path, artifact_path);
    const code = try runArgvResult(init.io, &[_][]const u8{
        runner,
        "yasm",
        source_path,
        artifact_path,
        log_path,
        "0",
        "validate",
    });
    if (code != 0) {
        try appendToolTrace(allocator, "yasm", "rosette-validate-failed", tool_args);
        std.process.exit(code);
    }
    try appendToolTrace(allocator, "yasm", "rosette-validate-passed", tool_args);
}

fn parseYasmInvocation(allocator: std.mem.Allocator, tool_args: []const []const u8) !YasmInvocation {
    var invocation = YasmInvocation{};
    var i: usize = 0;
    while (i < tool_args.len) : (i += 1) {
        const arg = tool_args[i];
        if (arg.len == 0) continue;
        if (std.mem.eql(u8, arg, "--")) {
            i += 1;
            while (i < tool_args.len) : (i += 1) {
                if (invocation.source_path == null) invocation.source_path = tool_args[i];
            }
            break;
        }
        if (std.mem.startsWith(u8, arg, "--")) {
            try parseYasmLongOption(&invocation, tool_args, &i, arg[2..]);
            continue;
        }
        if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
            try parseYasmShortOption(&invocation, tool_args, &i, arg);
            continue;
        }
        if (invocation.source_path == null) invocation.source_path = arg;
    }

    if (invocation.artifact_path == null) {
        if (invocation.source_path) |source| {
            invocation.artifact_path = try deriveYasmOutputPath(allocator, source, invocation.format);
        }
    }
    return invocation;
}

fn parseYasmShortOption(invocation: *YasmInvocation, tool_args: []const []const u8, i: *usize, arg: []const u8) !void {
    const opt = arg[1];
    const takes_value = switch (opt) {
        'a', 'f', 'g', 'L', 'l', 'm', 'o', 'p', 'r', 'D', 'I', 'W' => true,
        else => false,
    };
    if (!takes_value) return;

    const value = if (arg.len > 2) arg[2..] else nextArg(tool_args, i) orelse return;
    switch (opt) {
        'f' => invocation.format = value,
        'o' => invocation.artifact_path = value,
        else => {},
    }
}

fn parseYasmLongOption(invocation: *YasmInvocation, tool_args: []const []const u8, i: *usize, arg: []const u8) !void {
    const eq = std.mem.indexOfScalar(u8, arg, '=');
    const name = if (eq) |pos| arg[0..pos] else arg;
    const inline_value = if (eq) |pos| arg[pos + 1 ..] else null;
    if (std.ascii.eqlIgnoreCase(name, "oformat")) {
        invocation.format = inline_value orelse nextArg(tool_args, i) orelse return;
    } else if (std.ascii.eqlIgnoreCase(name, "objfile")) {
        invocation.artifact_path = inline_value orelse nextArg(tool_args, i) orelse return;
    } else if (std.ascii.eqlIgnoreCase(name, "list") or
        std.ascii.eqlIgnoreCase(name, "dformat") or
        std.ascii.eqlIgnoreCase(name, "lformat") or
        std.ascii.eqlIgnoreCase(name, "arch") or
        std.ascii.eqlIgnoreCase(name, "machine") or
        std.ascii.eqlIgnoreCase(name, "parser") or
        std.ascii.eqlIgnoreCase(name, "preproc"))
    {
        _ = inline_value orelse nextArg(tool_args, i) orelse return;
    }
}

fn nextArg(args: []const []const u8, i: *usize) ?[]const u8 {
    if (i.* + 1 >= args.len) return null;
    i.* += 1;
    return args[i.*];
}

fn deriveYasmOutputPath(allocator: std.mem.Allocator, source: []const u8, format: []const u8) ![]const u8 {
    if (std.mem.eql(u8, source, "-")) return try allocator.dupe(u8, "yasm.out");
    const extension: []const u8 = if (std.ascii.eqlIgnoreCase(format, "bin")) "" else ".o";
    const base_end = extensionPoint(source);
    if (extension.len == 0) return try allocator.dupe(u8, source[0..base_end]);
    return try std.mem.concat(allocator, u8, &.{ source[0..base_end], extension });
}

fn extensionPoint(path: []const u8) usize {
    var i = path.len;
    while (i > 0) {
        i -= 1;
        if (path[i] == '/' or path[i] == '\\') return path.len;
        if (path[i] == '.') return i;
    }
    return path.len;
}

fn yasmValidationLogPath(allocator: std.mem.Allocator, source_path: []const u8, artifact_path: []const u8) ![]const u8 {
    if (getenvSlice("ROSETTE_SHELL_PROJECT_DIR")) |project_dir| {
        const trace_dir = try std.fs.path.join(allocator, &.{ project_dir, ".rosette" });
        try makePathRecursive(allocator, trace_dir);
        const source_name = std.fs.path.basename(source_path);
        const log_name = try std.fmt.allocPrint(allocator, "{s}.yasm-abi.log", .{source_name});
        return try std.fs.path.join(allocator, &.{ trace_dir, log_name });
    }
    return try std.fmt.allocPrint(allocator, "{s}.yasm-abi.log", .{artifact_path});
}

fn detectProject(io: std.Io, allocator: std.mem.Allocator, project_dir: []const u8) !Detection {
    var score: u32 = 0;
    var has_yasm_elf64 = false;
    var has_cpp = false;
    var saw_makefile = false;
    var signals: std.ArrayList(u8) = .empty;

    if (try readProjectFile(io, allocator, project_dir, "Makefile")) |makefile| {
        saw_makefile = true;
        if (hasYasmElf64Makefile(makefile)) {
            score += 4;
            has_yasm_elf64 = true;
            try addSignal(&signals, allocator, "makefile:yasm-elf64");
        }
        if (containsIgnoreCase(makefile, "LD") and containsIgnoreCase(makefile, "ld -g")) {
            score += 1;
            try addSignal(&signals, allocator, "makefile:linux-ld");
        }
        if (containsIgnoreCase(makefile, "g++") and containsIgnoreCase(makefile, "-z noexecstack")) {
            score += 2;
            has_cpp = true;
            try addSignal(&signals, allocator, "makefile:linux-cxx");
        }
    }

    if (!saw_makefile) {
        if (try readProjectFile(io, allocator, project_dir, "makefile")) |makefile| {
            if (hasYasmElf64Makefile(makefile)) {
                score += 4;
                has_yasm_elf64 = true;
                try addSignal(&signals, allocator, "makefile:yasm-elf64");
            }
        }
    }

    try scoreAssemblyFiles(io, allocator, project_dir, &score, &signals);

    const detected = score >= 7 and has_yasm_elf64;
    const kind = if (has_cpp) "yasm-linux-elf64-cxx" else "yasm-linux-elf64";
    if (signals.items.len == 0) try signals.appendSlice(allocator, "none");

    return .{
        .detected = detected,
        .score = score,
        .kind = kind,
        .signals = signals.items,
    };
}

fn scoreAssemblyFiles(
    io: std.Io,
    allocator: std.mem.Allocator,
    project_dir: []const u8,
    score: *u32,
    signals: *std.ArrayList(u8),
) !void {
    var dir = std.Io.Dir.openDirAbsolute(io, project_dir, .{ .iterate = true }) catch return;
    defer dir.close(io);

    var it = dir.iterate();
    var files_seen: usize = 0;
    while (try it.next(io)) |entry| {
        if (!std.ascii.endsWithIgnoreCase(entry.name, ".asm")) continue;
        files_seen += 1;
        if (files_seen > 12) break;

        const path = try std.fs.path.join(allocator, &.{ project_dir, entry.name });
        const data = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(max_text_file)) catch continue;
        if (containsIgnoreCase(data, "Assignment:") or containsIgnoreCase(data, "Assignment #")) {
            score.* += 1;
            try addSignal(signals, allocator, "asm:assignment");
        }
        if (containsIgnoreCase(data, "section .text") or containsIgnoreCase(data, "section\t.text")) {
            score.* += 1;
            try addSignal(signals, allocator, "asm:text-section");
        }
        if (containsIgnoreCase(data, "global _start") or containsIgnoreCase(data, "global checkParams")) {
            score.* += 1;
            try addSignal(signals, allocator, "asm:globals");
        }
        if (containsIgnoreCase(data, "SYS_exit") or containsIgnoreCase(data, "SYS_read") or containsIgnoreCase(data, "SYS_write")) {
            score.* += 1;
            try addSignal(signals, allocator, "asm:linux-syscalls");
        }
        if (containsIgnoreCase(data, "syscall")) {
            score.* += 1;
            try addSignal(signals, allocator, "asm:syscall");
        }
    }
}

fn readProjectFile(io: std.Io, allocator: std.mem.Allocator, project_dir: []const u8, name: []const u8) !?[]u8 {
    const path = try std.fs.path.join(allocator, &.{ project_dir, name });
    return std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(max_text_file)) catch null;
}

fn appendMakeStartTrace(
    allocator: std.mem.Allocator,
    trace_path: []const u8,
    project_dir: []const u8,
    detection: Detection,
    make_args: []const []const u8,
) !void {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);

    try out.appendSlice(allocator, "# Rosette global shell trace\n");
    try out.appendSlice(allocator, "project = ");
    try out.appendSlice(allocator, project_dir);
    try out.append(allocator, '\n');
    try out.appendSlice(allocator, "kind = ");
    try out.appendSlice(allocator, detection.kind);
    try out.append(allocator, '\n');
    try out.appendSlice(allocator, "score = ");
    try appendInt(&out, allocator, detection.score);
    try out.append(allocator, '\n');
    try out.appendSlice(allocator, "signals = ");
    try out.appendSlice(allocator, detection.signals);
    try out.append(allocator, '\n');
    try out.appendSlice(allocator, "make_args = ");
    try appendArgs(&out, allocator, make_args);
    try out.append(allocator, '\n');
    try appendFilePath(allocator, trace_path, out.items);
}

fn appendToolTrace(allocator: std.mem.Allocator, tool_name: []const u8, strategy: []const u8, tool_args: []const []const u8) !void {
    const trace_path_raw = std.c.getenv("ROSETTE_SHELL_TRACE") orelse return;
    const trace_path = std.mem.sliceTo(trace_path_raw, 0);
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);

    try out.appendSlice(allocator, "tool[");
    try out.appendSlice(allocator, tool_name);
    try out.appendSlice(allocator, "] strategy=");
    try out.appendSlice(allocator, strategy);
    try out.appendSlice(allocator, " args=");
    try appendArgs(&out, allocator, tool_args);
    try out.append(allocator, '\n');
    try appendFilePath(allocator, trace_path, out.items);
}

fn buildMakeEnv(
    allocator: std.mem.Allocator,
    project_dir: []const u8,
    wrapper_dir: []const u8,
    helper_path: []const u8,
    trace_path: []const u8,
    kind: []const u8,
    source_root: []const u8,
    assembler_runner: ?[]const u8,
    recipe_shell_path: []const u8,
    elf_processor_path: ?[]const u8,
    config: ShellConfig,
    detection: Detection,
    make_args: []const []const u8,
) ![]const u8 {
    const current_path = getenvSlice("PATH") orelse "";
    const tmp = getenvSlice("TMPDIR") orelse "/tmp";
    const local_cache = try std.fs.path.join(allocator, &.{ tmp, "rosette-zig-cache" });
    const global_cache = try std.fs.path.join(allocator, &.{ tmp, "rosette-zig-global-cache" });
    const wrapped_path = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ wrapper_dir, current_path });

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, "# generated by rosette-shell prepare-make\n");
    try appendExport(&out, allocator, "ROSETTE_SHELL_ACTIVE", "1");
    try appendExport(&out, allocator, "ROSETTE_SHELL_PROJECT_KIND", kind);
    try appendExport(&out, allocator, "ROSETTE_SHELL_PROJECT_DIR", project_dir);
    try appendExport(&out, allocator, "ROSETTE_SHELL_TRACE", trace_path);
    try appendExport(&out, allocator, "ROSETTE_SHELL_HELPER", helper_path);
    try appendExport(&out, allocator, "ROSETTE_SHELL_WRAPPER_DIR", wrapper_dir);
    try appendExport(&out, allocator, "ROSETTE_SHELL_ORIGINAL_PATH", current_path);
    try appendExport(&out, allocator, "ROSETTE_RECIPE_SHELL", recipe_shell_path);
    if (source_root.len != 0) try appendExport(&out, allocator, "ROSETTE_SOURCE_ROOT", source_root);
    if (assembler_runner) |runner| try appendExport(&out, allocator, "ROSETTE_ASSEMBLER_RUNNER", runner);
    if (elf_processor_path) |processor| {
        try appendExport(&out, allocator, "ROSETTE_ELF_PROCESSOR", processor);
        try appendExport(&out, allocator, "RUNNER", processor);
        try appendExport(&out, allocator, "ELF_PROC", processor);
    }
    if (getenvSlice("ROSETTE_ELF_DUMP_RESULTS") == null and shouldEnableResultDump(config, detection, make_args)) {
        try appendExport(&out, allocator, "ROSETTE_ELF_DUMP_RESULTS", "1");
    }
    if (getenvSlice("ROSETTE_ELF_DUMP_ALL") == null and config.elf_dump_all_results) {
        try appendExport(&out, allocator, "ROSETTE_ELF_DUMP_ALL", "1");
    }
    if (getenvSlice("ROSETTE_GRAPHICS") == null) {
        try appendExport(&out, allocator, "ROSETTE_GRAPHICS", if (config.graphics_enabled) "on" else "off");
    }
    if (getenvSlice("ROSETTE_GRAPHICS_ENABLED") == null) {
        try appendExport(&out, allocator, "ROSETTE_GRAPHICS_ENABLED", if (config.graphics_enabled) "1" else "0");
    }
    try appendExport(&out, allocator, "PATH", wrapped_path);
    try appendExport(&out, allocator, "ZIG_LOCAL_CACHE_DIR", local_cache);
    try appendExport(&out, allocator, "ZIG_GLOBAL_CACHE_DIR", global_cache);
    try out.appendSlice(allocator, "unset MAKEFILES\n");
    return out.items;
}

fn buildShellSnippet(allocator: std.mem.Allocator, helper_path: []const u8, dyld_path: ?[]const u8, elf_processor_path: ?[]const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    const helper_dir = std.fs.path.dirname(helper_path) orelse "";
    if (helper_dir.len != 0) {
        try out.appendSlice(allocator, "export ROSETTE_BIN_DIR=");
        try appendShellQuoted(&out, allocator, helper_dir);
        try out.appendSlice(allocator,
            \\
            \\case ":$PATH:" in
            \\  *":$ROSETTE_BIN_DIR:"*) ;;
            \\  *) export PATH="$ROSETTE_BIN_DIR:$PATH" ;;
            \\esac
            \\
        );
    }

    try out.appendSlice(allocator, "export ROSETTE_SHELL_HELPER=");
    try appendShellQuoted(&out, allocator, helper_path);
    try out.appendSlice(allocator, "\n");

    if (dyld_path) |dyld| {
        try out.appendSlice(allocator, "export ROSETTE_DYLD_INTERPOSER=");
        try appendShellQuoted(&out, allocator, dyld);
        try out.appendSlice(allocator,
            \\
            \\__rosette_strip_dyld_interposer() {
            \\  if [ -z "${ROSETTE_DYLD_INTERPOSER:-}" ] || [ -z "${DYLD_INSERT_LIBRARIES:-}" ]; then
            \\    return 0
            \\  fi
            \\  local __rosette_dyld_old __rosette_dyld_new __rosette_dyld_part
            \\  __rosette_dyld_old="$DYLD_INSERT_LIBRARIES"
            \\  __rosette_dyld_new=
            \\  while [ -n "$__rosette_dyld_old" ]; do
            \\    case "$__rosette_dyld_old" in
            \\      *:*)
            \\        __rosette_dyld_part="${__rosette_dyld_old%%:*}"
            \\        __rosette_dyld_old="${__rosette_dyld_old#*:}"
            \\        ;;
            \\      *)
            \\        __rosette_dyld_part="$__rosette_dyld_old"
            \\        __rosette_dyld_old=
            \\        ;;
            \\    esac
            \\    [ "$__rosette_dyld_part" = "$ROSETTE_DYLD_INTERPOSER" ] && continue
            \\    if [ -z "$__rosette_dyld_new" ]; then
            \\      __rosette_dyld_new="$__rosette_dyld_part"
            \\    else
            \\      __rosette_dyld_new="$__rosette_dyld_new:$__rosette_dyld_part"
            \\    fi
            \\  done
            \\  if [ -n "$__rosette_dyld_new" ]; then
            \\    export DYLD_INSERT_LIBRARIES="$__rosette_dyld_new"
            \\  else
            \\    unset DYLD_INSERT_LIBRARIES
            \\  fi
            \\}
            \\
            \\# Global DYLD interposition is intentionally opt-in. Injecting a
            \\# library into every child process can break unrelated developer
            \\# tools; Rosette's make/direct-ELF paths do not require it.
            \\if [ "${ROSETTE_ENABLE_DYLD_INTERPOSE:-0}" = "1" ]; then
            \\  case ":${DYLD_INSERT_LIBRARIES:-}:" in
            \\    *":$ROSETTE_DYLD_INTERPOSER:"*) ;;
            \\    *) export DYLD_INSERT_LIBRARIES="$ROSETTE_DYLD_INTERPOSER${DYLD_INSERT_LIBRARIES:+:$DYLD_INSERT_LIBRARIES}" ;;
            \\  esac
            \\else
            \\  __rosette_strip_dyld_interposer
            \\fi
            \\
        );
    }

    if (elf_processor_path) |proc_path| {
        _ = proc_path;
        try out.appendSlice(allocator,
            \\export ROSETTE_ELF_PROCESSOR="$HOME/.rosette/bin/elf_processor"
            \\
        );
    }

    try out.appendSlice(allocator,
        \\export ROSETTE_ROUTER="$HOME/.rosette/bin/rosette-router"
        \\
    );

    try out.appendSlice(allocator,
        \\__rosette_reload_shell_integration() {
        \\  if [ -f "$HOME/.rosette/rosette-shell.sh" ]; then
        \\    . "$HOME/.rosette/rosette-shell.sh"
        \\  fi
        \\  if command -v __rosette_refresh_elf_commands >/dev/null 2>&1; then
        \\    __rosette_refresh_elf_commands >/dev/null 2>&1 || true
        \\  fi
        \\}
        \\
        \\__rosette_after_make() {
        \\  local __rosette_after_status="$1"
        \\  shift
        \\  local __rosette_after_arg
        \\  for __rosette_after_arg in "$@"; do
        \\    case "$__rosette_after_arg" in
        \\      shell|shell-update|install-shell)
        \\        __rosette_reload_shell_integration
        \\        return "$__rosette_after_status"
        \\        ;;
        \\    esac
        \\  done
        \\  if command -v __rosette_refresh_elf_commands >/dev/null 2>&1; then
        \\    __rosette_refresh_elf_commands >/dev/null 2>&1 || true
        \\  fi
        \\  return "$__rosette_after_status"
        \\}
        \\
        \\rosette-refresh() {
        \\  __rosette_reload_shell_integration
        \\}
        \\
        \\rosette-diagnose() {
        \\  if [ "$#" -gt 0 ]; then
        \\    "$ROSETTE_SHELL_HELPER" diagnose "$PWD" "$@"
        \\  else
        \\    "$ROSETTE_SHELL_HELPER" diagnose "$PWD"
        \\  fi
        \\}
        \\
        \\# zsh direct-launch support. This lets class-style x86-64 ELF
        \\# binaries run as ./program even though macOS cannot exec ELF.
        \\if [ -z "${ROSETTE_SHELL_DISABLE:-}" ] && [ -n "${ZSH_VERSION:-}" ]; then
        \\  eval '
        \\typeset -ga __rosette_elf_commands
        \\__rosette_exec_elf() {
        \\  emulate -L zsh
        \\  local __rosette_target="$1"
        \\  local __rosette_status __rosette_old_dyld __rosette_had_dyld=0
        \\  shift
        \\  if [ "${DYLD_INSERT_LIBRARIES+x}" = "x" ]; then
        \\    __rosette_had_dyld=1
        \\    __rosette_old_dyld="$DYLD_INSERT_LIBRARIES"
        \\    unset DYLD_INSERT_LIBRARIES
        \\  fi
        \\  "$ROSETTE_SHELL_HELPER" run-elf "$__rosette_target" "$@"
        \\  __rosette_status=$?
        \\  if [ "$__rosette_had_dyld" = "1" ]; then
        \\    export DYLD_INSERT_LIBRARIES="$__rosette_old_dyld"
        \\  fi
        \\  return "$__rosette_status"
        \\}
        \\__rosette_refresh_elf_commands() {
        \\  emulate -L zsh
        \\  local __rosette_cmd __rosette_path __rosette_proc __rosette_count=0
        \\  for __rosette_cmd in "${__rosette_elf_commands[@]}"; do
        \\    unfunction "$__rosette_cmd" 2>/dev/null || true
        \\  done
        \\  __rosette_elf_commands=()
        \\  if [ ! -x "$ROSETTE_SHELL_HELPER" ]; then
        \\    [ "${ROSETTE_SHELL_DEBUG:-0}" = "1" ] && print -r -- "rosette-shell: helper missing/not executable: $ROSETTE_SHELL_HELPER" >&2
        \\    return 0
        \\  fi
        \\  __rosette_proc="${ROSETTE_ELF_PROCESSOR:-$HOME/.rosette/bin/elf_processor}"
        \\  if [ ! -x "$__rosette_proc" ]; then
        \\    [ "${ROSETTE_SHELL_DEBUG:-0}" = "1" ] && print -r -- "rosette-shell: elf_processor missing/not executable: $__rosette_proc" >&2
        \\    return 0
        \\  fi
        \\  if ! "$ROSETTE_SHELL_HELPER" detect "$PWD" >/dev/null 2>&1; then
        \\    [ "${ROSETTE_SHELL_DEBUG:-0}" = "1" ] && print -r -- "rosette-shell: direct ELF launch disabled; project was not detected in $PWD" >&2
        \\    return 0
        \\  fi
        \\  for __rosette_path in ./*(N); do
        \\    [ -f "$__rosette_path" ] || continue
        \\    [ -x "$__rosette_path" ] || continue
        \\    if ! "$ROSETTE_SHELL_HELPER" is-elf64 "$__rosette_path" >/dev/null 2>&1; then
        \\      [ "${ROSETTE_SHELL_DEBUG:-0}" = "1" ] && print -r -- "rosette-shell: not x86-64 ELF: $__rosette_path" >&2
        \\      continue
        \\    fi
        \\    __rosette_cmd="./${__rosette_path:t}"
        \\    functions[$__rosette_cmd]="__rosette_exec_elf \"\$0\" \"\$@\""
        \\    __rosette_elf_commands+=("$__rosette_cmd")
        \\    __rosette_count=$((__rosette_count + 1))
        \\  done
        \\  [ "${ROSETTE_SHELL_DEBUG:-0}" = "1" ] && print -r -- "rosette-shell: registered $__rosette_count direct ELF launcher(s) in $PWD" >&2
        \\}
        \\rosette-diagnose-shell() {
        \\  emulate -L zsh
        \\  local __rosette_target="${1:-./ast01}"
        \\  "$ROSETTE_SHELL_HELPER" diagnose "$PWD" "$__rosette_target"
        \\  __rosette_refresh_elf_commands
        \\  if (( $+functions[$__rosette_target] )); then
        \\    print -r -- "  zsh_hook: $__rosette_target registered"
        \\  else
        \\    print -r -- "  zsh_hook: $__rosette_target NOT registered"
        \\    print -r -- "  repair: source ~/.rosette/rosette-shell.sh && rosette-refresh"
        \\  fi
        \\}
        \\autoload -Uz add-zsh-hook 2>/dev/null || true
        \\if (( $+functions[add-zsh-hook] )); then
        \\  add-zsh-hook chpwd __rosette_refresh_elf_commands 2>/dev/null || true
        \\  add-zsh-hook precmd __rosette_refresh_elf_commands 2>/dev/null || true
        \\fi
        \\__rosette_refresh_elf_commands 2>/dev/null || true
        \\'
        \\fi
        \\
        \\# Rosette shell integration. This does not replace make; it only
        \\# checks the current directory before delegating to command make.
        \\if [ -z "${ROSETTE_SHELL_DISABLE:-}" ]; then
        \\  if [ -x "$ROSETTE_SHELL_HELPER" ]; then
        \\    make() {
        \\      local __rosette_env __rosette_status __rosette_old_path
        \\      local __rosette_old_makefiles __rosette_had_makefiles
        \\      local __rosette_old_dyld __rosette_had_dyld
        \\      local __rosette_old_dump __rosette_had_dump
        \\      local __rosette_old_dump_all __rosette_had_dump_all
        \\      local __rosette_old_graphics __rosette_had_graphics
        \\      local __rosette_old_graphics_enabled __rosette_had_graphics_enabled
        \\      local __rosette_old_runner __rosette_had_runner
        \\      local __rosette_old_elf_proc __rosette_had_elf_proc
        \\      local __rosette_old_zig_local __rosette_had_zig_local
        \\      local __rosette_old_zig_global __rosette_had_zig_global
        \\      __rosette_env="${TMPDIR:-/tmp}/rosette-shell-env.$$"
        \\      __rosette_old_path="$PATH"
        \\      __rosette_had_makefiles=0
        \\      __rosette_had_dyld=0
        \\      __rosette_had_dump=0
        \\      __rosette_had_dump_all=0
        \\      __rosette_had_graphics=0
        \\      __rosette_had_graphics_enabled=0
        \\      __rosette_had_runner=0
        \\      __rosette_had_elf_proc=0
        \\      __rosette_had_zig_local=0
        \\      __rosette_had_zig_global=0
        \\      if [ "${MAKEFILES+x}" = "x" ]; then
        \\        __rosette_had_makefiles=1
        \\        __rosette_old_makefiles="$MAKEFILES"
        \\      fi
        \\      if [ "${ROSETTE_ELF_DUMP_RESULTS+x}" = "x" ]; then
        \\        __rosette_had_dump=1
        \\        __rosette_old_dump="$ROSETTE_ELF_DUMP_RESULTS"
        \\      fi
        \\      if [ "${ROSETTE_ELF_DUMP_ALL+x}" = "x" ]; then
        \\        __rosette_had_dump_all=1
        \\        __rosette_old_dump_all="$ROSETTE_ELF_DUMP_ALL"
        \\      fi
        \\      if [ "${ROSETTE_GRAPHICS+x}" = "x" ]; then
        \\        __rosette_had_graphics=1
        \\        __rosette_old_graphics="$ROSETTE_GRAPHICS"
        \\      fi
        \\      if [ "${ROSETTE_GRAPHICS_ENABLED+x}" = "x" ]; then
        \\        __rosette_had_graphics_enabled=1
        \\        __rosette_old_graphics_enabled="$ROSETTE_GRAPHICS_ENABLED"
        \\      fi
        \\      if [ "${RUNNER+x}" = "x" ]; then
        \\        __rosette_had_runner=1
        \\        __rosette_old_runner="$RUNNER"
        \\      fi
        \\      if [ "${ELF_PROC+x}" = "x" ]; then
        \\        __rosette_had_elf_proc=1
        \\        __rosette_old_elf_proc="$ELF_PROC"
        \\      fi
        \\      if [ "${ZIG_LOCAL_CACHE_DIR+x}" = "x" ]; then
        \\        __rosette_had_zig_local=1
        \\        __rosette_old_zig_local="$ZIG_LOCAL_CACHE_DIR"
        \\      fi
        \\      if [ "${ZIG_GLOBAL_CACHE_DIR+x}" = "x" ]; then
        \\        __rosette_had_zig_global=1
        \\        __rosette_old_zig_global="$ZIG_GLOBAL_CACHE_DIR"
        \\      fi
        \\      if [ "${DYLD_INSERT_LIBRARIES+x}" = "x" ]; then
        \\        __rosette_had_dyld=1
        \\        __rosette_old_dyld="$DYLD_INSERT_LIBRARIES"
        \\        unset DYLD_INSERT_LIBRARIES
        \\      fi
        \\      if "$ROSETTE_SHELL_HELPER" prepare-make "$PWD" "$__rosette_env" "$@" >/dev/null 2>&1; then
        \\        . "$__rosette_env"
        \\        rm -f "$__rosette_env"
        \\        if [ -n "${ROSETTE_RECIPE_SHELL:-}" ]; then
        \\          command make SHELL="$ROSETTE_RECIPE_SHELL" "$@"
        \\        else
        \\          command make "$@"
        \\        fi
        \\        __rosette_status=$?
        \\        "$ROSETTE_SHELL_HELPER" finish-make "$PWD" "$__rosette_status" "$@" >/dev/null 2>&1 || true
        \\        PATH="$__rosette_old_path"
        \\        if [ "$__rosette_had_makefiles" = "1" ]; then
        \\          export MAKEFILES="$__rosette_old_makefiles"
        \\        else
        \\          unset MAKEFILES
        \\        fi
        \\        unset ROSETTE_SHELL_ACTIVE ROSETTE_SHELL_PROJECT_KIND ROSETTE_SHELL_PROJECT_DIR
        \\        unset ROSETTE_SHELL_TRACE ROSETTE_SHELL_WRAPPER_DIR ROSETTE_SHELL_ORIGINAL_PATH
        \\        unset ROSETTE_RECIPE_SHELL
        \\        if [ "$__rosette_had_dump" = "1" ]; then
        \\          export ROSETTE_ELF_DUMP_RESULTS="$__rosette_old_dump"
        \\        else
        \\          unset ROSETTE_ELF_DUMP_RESULTS
        \\        fi
        \\        if [ "$__rosette_had_dump_all" = "1" ]; then
        \\          export ROSETTE_ELF_DUMP_ALL="$__rosette_old_dump_all"
        \\        else
        \\          unset ROSETTE_ELF_DUMP_ALL
        \\        fi
        \\        if [ "$__rosette_had_graphics" = "1" ]; then
        \\          export ROSETTE_GRAPHICS="$__rosette_old_graphics"
        \\        else
        \\          unset ROSETTE_GRAPHICS
        \\        fi
        \\        if [ "$__rosette_had_graphics_enabled" = "1" ]; then
        \\          export ROSETTE_GRAPHICS_ENABLED="$__rosette_old_graphics_enabled"
        \\        else
        \\          unset ROSETTE_GRAPHICS_ENABLED
        \\        fi
        \\        if [ "$__rosette_had_runner" = "1" ]; then
        \\          export RUNNER="$__rosette_old_runner"
        \\        else
        \\          unset RUNNER
        \\        fi
        \\        if [ "$__rosette_had_elf_proc" = "1" ]; then
        \\          export ELF_PROC="$__rosette_old_elf_proc"
        \\        else
        \\          unset ELF_PROC
        \\        fi
        \\        if [ "$__rosette_had_zig_local" = "1" ]; then
        \\          export ZIG_LOCAL_CACHE_DIR="$__rosette_old_zig_local"
        \\        else
        \\          unset ZIG_LOCAL_CACHE_DIR
        \\        fi
        \\        if [ "$__rosette_had_zig_global" = "1" ]; then
        \\          export ZIG_GLOBAL_CACHE_DIR="$__rosette_old_zig_global"
        \\        else
        \\          unset ZIG_GLOBAL_CACHE_DIR
        \\        fi
        \\        if [ "$__rosette_had_dyld" = "1" ]; then
        \\          export DYLD_INSERT_LIBRARIES="$__rosette_old_dyld"
        \\        else
        \\          unset DYLD_INSERT_LIBRARIES
        \\        fi
        \\        __rosette_after_make "$__rosette_status" "$@"
        \\        return "$?"
        \\      fi
        \\      rm -f "$__rosette_env"
        \\      PATH="$__rosette_old_path"
        \\      if [ "$__rosette_had_dump" = "1" ]; then
        \\        export ROSETTE_ELF_DUMP_RESULTS="$__rosette_old_dump"
        \\      else
        \\        unset ROSETTE_ELF_DUMP_RESULTS
        \\      fi
        \\      if [ "$__rosette_had_dump_all" = "1" ]; then
        \\        export ROSETTE_ELF_DUMP_ALL="$__rosette_old_dump_all"
        \\      else
        \\        unset ROSETTE_ELF_DUMP_ALL
        \\      fi
        \\      if [ "$__rosette_had_graphics" = "1" ]; then
        \\        export ROSETTE_GRAPHICS="$__rosette_old_graphics"
        \\      else
        \\        unset ROSETTE_GRAPHICS
        \\      fi
        \\      if [ "$__rosette_had_graphics_enabled" = "1" ]; then
        \\        export ROSETTE_GRAPHICS_ENABLED="$__rosette_old_graphics_enabled"
        \\      else
        \\        unset ROSETTE_GRAPHICS_ENABLED
        \\      fi
        \\      if [ "$__rosette_had_runner" = "1" ]; then
        \\        export RUNNER="$__rosette_old_runner"
        \\      else
        \\        unset RUNNER
        \\      fi
        \\      if [ "$__rosette_had_elf_proc" = "1" ]; then
        \\        export ELF_PROC="$__rosette_old_elf_proc"
        \\      else
        \\        unset ELF_PROC
        \\      fi
        \\      if [ "$__rosette_had_zig_local" = "1" ]; then
        \\        export ZIG_LOCAL_CACHE_DIR="$__rosette_old_zig_local"
        \\      else
        \\        unset ZIG_LOCAL_CACHE_DIR
        \\      fi
        \\      if [ "$__rosette_had_zig_global" = "1" ]; then
        \\        export ZIG_GLOBAL_CACHE_DIR="$__rosette_old_zig_global"
        \\      else
        \\        unset ZIG_GLOBAL_CACHE_DIR
        \\      fi
        \\      if [ "$__rosette_had_dyld" = "1" ]; then
        \\        export DYLD_INSERT_LIBRARIES="$__rosette_old_dyld"
        \\      else
        \\        unset DYLD_INSERT_LIBRARIES
        \\      fi
        \\      command make "$@"
        \\      __rosette_status=$?
        \\      __rosette_after_make "$__rosette_status" "$@"
        \\      return "$?"
        \\    }
        \\  fi
        \\fi
        \\
    );
    return out.items;
}

fn buildProfileBlock(allocator: std.mem.Allocator) ![]const u8 {
    return try std.fmt.allocPrint(allocator,
        \\{s}
        \\[ -f "$HOME/.rosette/rosette-shell.sh" ] && . "$HOME/.rosette/rosette-shell.sh"
        \\{s}
        \\
    , .{ block_begin, block_end });
}

fn installProfileBlocks(io: std.Io, allocator: std.mem.Allocator, home: []const u8, block: []const u8) !void {
    var targets: std.ArrayList(ProfileTarget) = .empty;
    defer targets.deinit(allocator);
    try collectProfileTargets(allocator, home, true, &targets);

    for (targets.items) |target| {
        try ensureProfileBlock(io, allocator, target.path, block, target.create);
        if (target.create or fileExists(allocator, target.path)) {
            std.debug.print("profile: {s}\n", .{target.path});
        }
    }
}

fn removeProfileBlocks(io: std.Io, allocator: std.mem.Allocator, home: []const u8) !void {
    var targets: std.ArrayList(ProfileTarget) = .empty;
    defer targets.deinit(allocator);
    try collectProfileTargets(allocator, home, false, &targets);

    for (targets.items) |target| {
        try removeProfileBlock(io, allocator, target.path);
    }
}

fn collectProfileTargets(
    allocator: std.mem.Allocator,
    home: []const u8,
    for_install: bool,
    targets: *std.ArrayList(ProfileTarget),
) !void {
    const shell_path = getenvSlice("SHELL") orelse "";
    const shell_name = std.fs.path.basename(shell_path);
    const shell_known = shell_name.len != 0;
    const shell_is_zsh = std.mem.eql(u8, shell_name, "zsh");
    const shell_is_bash = std.mem.eql(u8, shell_name, "bash");
    const prefer_zsh = shell_is_zsh or (!shell_known and comptime builtin.target.os.tag == .macos);

    const zdot = try zshDotDir(allocator, home);
    const zshrc = try std.fs.path.join(allocator, &.{ zdot, ".zshrc" });
    const zprofile = try std.fs.path.join(allocator, &.{ zdot, ".zprofile" });
    try addProfileTarget(targets, allocator, zshrc, for_install and prefer_zsh);
    try addProfileTarget(targets, allocator, zprofile, false);

    const home_zshrc = try std.fs.path.join(allocator, &.{ home, ".zshrc" });
    const home_zprofile = try std.fs.path.join(allocator, &.{ home, ".zprofile" });
    try addProfileTarget(targets, allocator, home_zshrc, for_install and prefer_zsh and std.mem.eql(u8, zdot, home));
    try addProfileTarget(targets, allocator, home_zprofile, false);

    const bashrc = try std.fs.path.join(allocator, &.{ home, ".bashrc" });
    const bash_profile = try std.fs.path.join(allocator, &.{ home, ".bash_profile" });
    try addProfileTarget(targets, allocator, bashrc, for_install and shell_is_bash);
    try addProfileTarget(targets, allocator, bash_profile, for_install and shell_is_bash);

    if (for_install and !shell_is_zsh and !shell_is_bash and shell_known) {
        std.debug.print("rosette-shell: warning: shell '{s}' is not directly managed; install added compatible zsh/bash profile hooks where present\n", .{shell_name});
    }
}

fn addProfileTarget(targets: *std.ArrayList(ProfileTarget), allocator: std.mem.Allocator, path: []const u8, create: bool) !void {
    for (targets.items) |*target| {
        if (std.mem.eql(u8, target.path, path)) {
            target.create = target.create or create;
            return;
        }
    }
    try targets.append(allocator, .{ .path = path, .create = create });
}

fn zshDotDir(allocator: std.mem.Allocator, home: []const u8) ![]const u8 {
    const raw = getenvSlice("ZDOTDIR") orelse return home;
    if (raw.len == 0) return home;
    if (std.fs.path.isAbsolute(raw)) return try allocator.dupe(u8, raw);
    return try std.fs.path.resolve(allocator, &.{ home, raw });
}

fn ensureProfileBlock(io: std.Io, allocator: std.mem.Allocator, path: []const u8, block: []const u8, create_if_missing: bool) !void {
    const existing = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => {
            if (!create_if_missing) return;
            try writeFilePath(allocator, path, block);
            return;
        },
        else => return err,
    };

    const updated = try replaceManagedBlock(allocator, existing, block);
    if (!std.mem.eql(u8, existing, updated)) try writeFilePath(allocator, path, updated);
}

fn removeProfileBlock(io: std.Io, allocator: std.mem.Allocator, path: []const u8) !void {
    const existing = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(1024 * 1024)) catch return;
    const removed = try removeManagedBlock(allocator, existing);
    if (!std.mem.eql(u8, existing, removed)) try writeFilePath(allocator, path, removed);
}

fn replaceManagedBlock(allocator: std.mem.Allocator, existing: []const u8, block: []const u8) ![]const u8 {
    const begin = std.mem.indexOf(u8, existing, block_begin);
    if (begin) |start| {
        if (std.mem.indexOfPos(u8, existing, start, block_end)) |end_start| {
            var end = end_start + block_end.len;
            if (end < existing.len and existing[end] == '\n') end += 1;
            var out: std.ArrayList(u8) = .empty;
            errdefer out.deinit(allocator);
            try out.appendSlice(allocator, existing[0..start]);
            try out.appendSlice(allocator, block);
            try out.appendSlice(allocator, existing[end..]);
            return out.items;
        }
    }

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, existing);
    if (existing.len != 0 and existing[existing.len - 1] != '\n') try out.append(allocator, '\n');
    try out.appendSlice(allocator, block);
    return out.items;
}

fn removeManagedBlock(allocator: std.mem.Allocator, existing: []const u8) ![]const u8 {
    const begin = std.mem.indexOf(u8, existing, block_begin) orelse return existing;
    const end_start = std.mem.indexOfPos(u8, existing, begin, block_end) orelse return existing;
    var end = end_start + block_end.len;
    if (end < existing.len and existing[end] == '\n') end += 1;

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, existing[0..begin]);
    try out.appendSlice(allocator, existing[end..]);
    return out.items;
}

fn ensureWrappers(allocator: std.mem.Allocator, wrapper_dir: []const u8, helper_path: []const u8) !void {
    try makePathRecursive(allocator, wrapper_dir);
    const tools = [_][]const u8{ "yasm", "ld", "g++", "c++", "gcc", "cc", "clang", "clang++" };
    for (tools) |tool| {
        const path = try std.fs.path.join(allocator, &.{ wrapper_dir, tool });
        const script = try std.fmt.allocPrint(allocator,
            \\#!/bin/sh
            \\unset DYLD_INSERT_LIBRARIES
            \\exec "{s}" tool "{s}" "$@"
            \\
        , .{ helper_path, tool });
        try writeFilePath(allocator, path, script);
        try chmodPath(allocator, path, 0o755);
    }

    const recipe_shell_path = try std.fs.path.join(allocator, &.{ wrapper_dir, "rosette-sh" });
    try unlinkIfExists(allocator, recipe_shell_path);

    const elf_processor_wrapper = try std.fs.path.join(allocator, &.{ wrapper_dir, "elf_processor" });
    const elf_processor_script =
        \\#!/bin/sh
        \\unset DYLD_INSERT_LIBRARIES
        \\if [ -n "${ROSETTE_ELF_PROCESSOR:-}" ] && [ -x "$ROSETTE_ELF_PROCESSOR" ]; then
        \\  exec "$ROSETTE_ELF_PROCESSOR" "$@"
        \\fi
        \\if [ -x "$HOME/.rosette/bin/elf_processor" ]; then
        \\  exec "$HOME/.rosette/bin/elf_processor" "$@"
        \\fi
        \\echo "rosette-shell: elf_processor is not installed; run 'make shell-update' from Rosette." >&2
        \\exit 127
        \\
    ;
    try writeFilePath(allocator, elf_processor_wrapper, elf_processor_script);
    try chmodPath(allocator, elf_processor_wrapper, 0o755);
}

fn removeWrappers(allocator: std.mem.Allocator, wrapper_dir: []const u8) !void {
    const tools = [_][]const u8{ "yasm", "ld", "g++", "c++", "gcc", "cc", "clang", "clang++" };
    for (tools) |tool| {
        const path = try std.fs.path.join(allocator, &.{ wrapper_dir, tool });
        try unlinkIfExists(allocator, path);
    }
    const recipe_shell_path = try std.fs.path.join(allocator, &.{ wrapper_dir, "rosette-sh" });
    try unlinkIfExists(allocator, recipe_shell_path);
    const elf_processor_wrapper = try std.fs.path.join(allocator, &.{ wrapper_dir, "elf_processor" });
    try unlinkIfExists(allocator, elf_processor_wrapper);
}

fn copySelf(init: std.process.Init, allocator: std.mem.Allocator, destination: []const u8) !void {
    const self_path = try std.process.executablePathAlloc(init.io, allocator);
    const resolved_dest = try std.fs.path.resolve(allocator, &.{destination});
    const resolved_self = try std.fs.path.resolve(allocator, &.{self_path});
    if (std.mem.eql(u8, resolved_self, resolved_dest)) {
        try chmodPath(allocator, destination, 0o755);
        return;
    }

    const bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, self_path, allocator, .unlimited);
    try writeFilePath(allocator, destination, bytes);
    try chmodPath(allocator, destination, 0o755);
}

fn currentHelperPath(init: std.process.Init, allocator: std.mem.Allocator) ![]const u8 {
    if (getenvSlice("ROSETTE_SHELL_HELPER")) |helper| return try allocator.dupe(u8, helper);
    return try std.process.executablePathAlloc(init.io, allocator);
}

fn currentSourceRoot(io: std.Io, allocator: std.mem.Allocator) ![]const u8 {
    if (getenvSlice("ROSETTE_SOURCE_ROOT")) |root_path| return try allocator.dupe(u8, root_path);
    const home = homeDir(allocator) catch return "";
    const config_path = try std.fs.path.join(allocator, &.{ home, ".rosette", "source-root" });
    const contents = std.Io.Dir.cwd().readFileAlloc(io, config_path, allocator, .limited(16 * 1024)) catch return "";
    return try allocator.dupe(u8, std.mem.trim(u8, contents, " \t\r\n"));
}

fn configPath(allocator: std.mem.Allocator) ![]const u8 {
    const home = try homeDir(allocator);
    return try std.fs.path.join(allocator, &.{ home, ".rosette", "config.toml" });
}

fn printConfig(io: std.Io, allocator: std.mem.Allocator) !void {
    const path = try configPath(allocator);
    const config = try loadShellConfig(io, allocator);
    std.debug.print("Rosette config: {s}\n", .{path});
    std.debug.print("  [elf] dump_results = \"{s}\"\n", .{configModeName(config.elf_dump_results)});
    std.debug.print("  [elf] dump_all_results = {s}\n", .{if (config.elf_dump_all_results) "true" else "false"});
    std.debug.print("  [graphics] enabled = {s}\n", .{if (config.graphics_enabled) "true" else "false"});
    std.debug.print("\nUseful commands:\n", .{});
    std.debug.print("  rosette config-path\n", .{});
    std.debug.print("  rosette clean-state\n", .{});
    std.debug.print("  make run or ./program    # auto-dumps assignment results when configured\n", .{});
}

fn loadShellConfig(io: std.Io, allocator: std.mem.Allocator) !ShellConfig {
    const path = try configPath(allocator);
    const contents = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(64 * 1024)) catch return .{};
    return parseShellConfig(contents);
}

fn parseShellConfig(contents: []const u8) ShellConfig {
    var config = ShellConfig{};
    var section: []const u8 = "";
    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |raw_line| {
        const no_comment = if (std.mem.indexOfScalar(u8, raw_line, '#')) |pos| raw_line[0..pos] else raw_line;
        const line = std.mem.trim(u8, no_comment, " \t\r\n");
        if (line.len == 0) continue;

        if (line[0] == '[' and line[line.len - 1] == ']') {
            section = std.mem.trim(u8, line[1 .. line.len - 1], " \t\r\n");
            continue;
        }

        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const key = std.mem.trim(u8, line[0..eq], " \t\r\n");
        const value = trimTomlValue(std.mem.trim(u8, line[eq + 1 ..], " \t\r\n"));

        if ((std.ascii.eqlIgnoreCase(section, "elf") and std.ascii.eqlIgnoreCase(key, "dump_results")) or
            std.ascii.eqlIgnoreCase(key, "ROSETTE_ELF_DUMP_RESULTS"))
        {
            config.elf_dump_results = parseConfigMode(value) orelse config.elf_dump_results;
        } else if ((std.ascii.eqlIgnoreCase(section, "elf") and std.ascii.eqlIgnoreCase(key, "dump_all_results")) or
            std.ascii.eqlIgnoreCase(key, "ROSETTE_ELF_DUMP_ALL") or
            std.ascii.eqlIgnoreCase(key, "ROSETTE_ELF_DUMP_ALL_RESULTS"))
        {
            config.elf_dump_all_results = parseConfigBool(value) orelse config.elf_dump_all_results;
        } else if ((std.ascii.eqlIgnoreCase(section, "graphics") and std.ascii.eqlIgnoreCase(key, "enabled")) or
            std.ascii.eqlIgnoreCase(key, "GRAPHICS"))
        {
            config.graphics_enabled = parseConfigBool(value) orelse config.graphics_enabled;
        }
    }
    return config;
}

fn trimTomlValue(value: []const u8) []const u8 {
    if (value.len >= 2) {
        const first = value[0];
        const last = value[value.len - 1];
        if ((first == '"' and last == '"') or (first == '\'' and last == '\'')) {
            return value[1 .. value.len - 1];
        }
    }
    return value;
}

fn parseConfigMode(value: []const u8) ?ConfigMode {
    if (std.ascii.eqlIgnoreCase(value, "auto")) return .auto;
    if (parseConfigBool(value)) |enabled| return if (enabled) .on else .off;
    if (std.ascii.eqlIgnoreCase(value, "on") or std.ascii.eqlIgnoreCase(value, "enabled")) return .on;
    if (std.ascii.eqlIgnoreCase(value, "off") or std.ascii.eqlIgnoreCase(value, "disabled")) return .off;
    return null;
}

fn parseConfigBool(value: []const u8) ?bool {
    if (std.mem.eql(u8, value, "1") or
        std.ascii.eqlIgnoreCase(value, "true") or
        std.ascii.eqlIgnoreCase(value, "yes") or
        std.ascii.eqlIgnoreCase(value, "on") or
        std.ascii.eqlIgnoreCase(value, "enabled"))
    {
        return true;
    }
    if (std.mem.eql(u8, value, "0") or
        std.ascii.eqlIgnoreCase(value, "false") or
        std.ascii.eqlIgnoreCase(value, "no") or
        std.ascii.eqlIgnoreCase(value, "off") or
        std.ascii.eqlIgnoreCase(value, "disabled"))
    {
        return false;
    }
    return null;
}

fn configModeName(mode: ConfigMode) []const u8 {
    return switch (mode) {
        .off => "off",
        .on => "on",
        .auto => "auto",
    };
}

fn shouldEnableResultDump(config: ShellConfig, detection: Detection, make_args: []const []const u8) bool {
    return switch (config.elf_dump_results) {
        .off => false,
        .on => true,
        .auto => makeArgsRequestRun(make_args) and
            detection.detected and
            containsIgnoreCase(detection.kind, "yasm-linux-elf64"),
    };
}

fn shouldEnableDirectResultDump(config: ShellConfig, detection: Detection) bool {
    return switch (config.elf_dump_results) {
        .off => false,
        .on => true,
        .auto => detection.detected and
            containsIgnoreCase(detection.kind, "yasm-linux-elf64"),
    };
}

fn makeArgsRequestRun(make_args: []const []const u8) bool {
    for (make_args) |arg| {
        if (std.mem.eql(u8, arg, "run")) return true;
    }
    return false;
}

fn resolveElfProcessorPath(allocator: std.mem.Allocator) ![]const u8 {
    if (getenvSlice("ROSETTE_ELF_PROCESSOR")) |env_elf_path| {
        if (canExecute(allocator, env_elf_path) or fileExists(allocator, env_elf_path)) {
            return try allocator.dupe(u8, env_elf_path);
        }
    }
    const home = try homeDir(allocator);
    return try std.fs.path.join(allocator, &.{ home, ".rosette", "bin", "elf_processor" });
}

fn resolveCompatRouterPath(init: std.process.Init, allocator: std.mem.Allocator) ![]const u8 {
    if (getenvSlice("ROSETTE_ROUTER")) |router_path| {
        if (canExecute(allocator, router_path) or fileExists(allocator, router_path)) {
            return try allocator.dupe(u8, router_path);
        }
    }

    const self_path = std.process.executablePathAlloc(init.io, allocator) catch "";
    if (self_path.len != 0) {
        if (std.fs.path.dirname(self_path)) |self_dir| {
            const sibling = try std.fs.path.join(allocator, &.{ self_dir, "rosette-router" });
            if (canExecute(allocator, sibling) or fileExists(allocator, sibling)) return sibling;
        }
    }

    const source_root = currentSourceRoot(init.io, allocator) catch "";
    if (source_root.len != 0) {
        const from_source = try std.fs.path.join(allocator, &.{ source_root, "zig-out", "bin", "rosette-router" });
        if (canExecute(allocator, from_source) or fileExists(allocator, from_source)) return from_source;
    }

    const cwd_candidate = try std.fs.path.join(allocator, &.{ "zig-out", "bin", "rosette-router" });
    if (canExecute(allocator, cwd_candidate) or fileExists(allocator, cwd_candidate)) return cwd_candidate;

    const helper_path = currentHelperPath(init, allocator) catch "";
    if (helper_path.len != 0) {
        if (std.fs.path.dirname(helper_path)) |helper_dir| {
            const sibling = try std.fs.path.join(allocator, &.{ helper_dir, "rosette-router" });
            if (canExecute(allocator, sibling) or fileExists(allocator, sibling)) return sibling;
        }
    }

    const home = try homeDir(allocator);
    return try std.fs.path.join(allocator, &.{ home, ".rosette", "bin", "rosette-router" });
}

fn resolveAssemblerRunner(allocator: std.mem.Allocator, helper_path: []const u8, source_root: []const u8) !?[]const u8 {
    if (getenvSlice("ROSETTE_ASSEMBLER_RUNNER")) |runner| {
        if (canExecute(allocator, runner)) return try allocator.dupe(u8, runner);
    }

    if (helper_path.len != 0) {
        if (std.fs.path.dirname(helper_path)) |helper_dir| {
            if (try executableCandidate(allocator, &.{ helper_dir, "rosette_assembler_runner" })) |runner| return runner;
        }
    }

    if (source_root.len != 0) {
        if (try executableCandidate(allocator, &.{ source_root, "zig-out", "bin", "rosette_assembler_runner" })) |runner| return runner;
        if (try executableCandidate(allocator, &.{ source_root, "rosette_assembler_runner" })) |runner| return runner;
        if (try executableCandidate(allocator, &.{ source_root, "..", "..", "MacOS", "rosette_assembler_runner" })) |runner| return runner;
    }

    return null;
}

fn executableCandidate(allocator: std.mem.Allocator, parts: []const []const u8) !?[]const u8 {
    const joined = try std.fs.path.join(allocator, parts);
    const resolved = std.fs.path.resolve(allocator, &.{joined}) catch joined;
    if (canExecute(allocator, resolved)) return resolved;
    return null;
}

fn runNativeTool(io: std.Io, allocator: std.mem.Allocator, tool_name: []const u8, tool_args: []const []const u8) !u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);
    try argv.append(allocator, try resolveToolPath(allocator, tool_name));
    for (tool_args) |arg| try argv.append(allocator, arg);
    return try runArgvResult(io, argv.items);
}

fn execZigLd(io: std.Io, allocator: std.mem.Allocator, tool_args: []const []const u8) !void {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);
    try argv.append(allocator, try resolveToolPath(allocator, "zig"));
    try argv.append(allocator, "cc");
    try argv.append(allocator, "-target");
    try argv.append(allocator, "x86_64-linux-gnu");
    try argv.append(allocator, "-nostdlib");
    try appendFilteredLinuxArgs(&argv, allocator, tool_args, true);
    try execArgv(io, argv.items);
}

fn runZigCompilerWithCompatibility(
    io: std.Io,
    allocator: std.mem.Allocator,
    tool_name: []const u8,
    zig_mode: []const u8,
    tool_args: []const []const u8,
    cxx_compat: bool,
) !void {
    const invocation = try parseCompilerInvocation(allocator, tool_args);
    if (cxx_compat and !invocation.compile_only) {
        const repaired = try repairCxxLinkObjects(io, allocator, tool_args);
        if (repaired != 0) try appendToolTrace(allocator, tool_name, "weaken-cxx-placeholders-before-link", tool_args);
    }

    const code = try runZigCompiler(io, allocator, zig_mode, tool_args);
    if (code != 0) std.process.exit(code);

    if (cxx_compat and invocation.compile_only) {
        if (invocation.artifact_path) |artifact_path| {
            const repaired = try weakenCompiledCxxObject(io, allocator, artifact_path);
            if (repaired != 0) try appendToolTrace(allocator, tool_name, "weaken-cxx-placeholders-after-compile", &[_][]const u8{artifact_path});
        }
    }
    std.process.exit(0);
}

fn runZigCompiler(io: std.Io, allocator: std.mem.Allocator, zig_mode: []const u8, tool_args: []const []const u8) !u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);
    try argv.append(allocator, try resolveToolPath(allocator, "zig"));
    try argv.append(allocator, zig_mode);
    try argv.append(allocator, "-target");
    try argv.append(allocator, "x86_64-linux-gnu");
    try argv.append(allocator, "-w");
    try argv.append(allocator, "-Wno-nullability-completeness");
    try appendFilteredLinuxArgs(&argv, allocator, tool_args, false);
    return try runArgvResult(io, argv.items);
}

fn parseCompilerInvocation(allocator: std.mem.Allocator, tool_args: []const []const u8) !CompileInvocation {
    var invocation = CompileInvocation{};
    var i: usize = 0;
    while (i < tool_args.len) : (i += 1) {
        const arg = tool_args[i];
        if (arg.len == 0) continue;
        if (std.mem.eql(u8, arg, "-c")) {
            invocation.compile_only = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "-o")) {
            if (nextArg(tool_args, &i)) |value| invocation.artifact_path = value;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "-o") and arg.len > 2) {
            invocation.artifact_path = arg[2..];
            continue;
        }
        if (compilerOptionTakesValue(arg)) {
            _ = nextArg(tool_args, &i);
            continue;
        }
        if (isSourceFile(arg) and invocation.source_path == null) invocation.source_path = arg;
    }

    if (invocation.compile_only and invocation.artifact_path == null) {
        if (invocation.source_path) |source_path| {
            invocation.artifact_path = try deriveObjectOutputPath(allocator, source_path);
        }
    }
    return invocation;
}

fn compilerOptionTakesValue(arg: []const u8) bool {
    const value_options = [_][]const u8{
        "-x",
        "-include",
        "-isystem",
        "-idirafter",
        "-iquote",
        "-I",
        "-D",
        "-U",
        "-L",
        "-l",
        "-framework",
        "-Xlinker",
        "-Xclang",
        "-MF",
        "-MT",
        "-MQ",
        "-z",
    };
    for (value_options) |option| {
        if (std.mem.eql(u8, arg, option)) return true;
    }
    return false;
}

fn deriveObjectOutputPath(allocator: std.mem.Allocator, source: []const u8) ![]const u8 {
    const base_end = extensionPoint(source);
    return try std.mem.concat(allocator, u8, &.{ source[0..base_end], ".o" });
}

fn isSourceFile(path: []const u8) bool {
    return std.ascii.endsWithIgnoreCase(path, ".c") or
        std.ascii.endsWithIgnoreCase(path, ".cc") or
        std.ascii.endsWithIgnoreCase(path, ".cpp") or
        std.ascii.endsWithIgnoreCase(path, ".cxx") or
        std.ascii.endsWithIgnoreCase(path, ".C");
}

fn isObjectFile(path: []const u8) bool {
    return std.ascii.endsWithIgnoreCase(path, ".o") or
        std.ascii.endsWithIgnoreCase(path, ".obj");
}

fn repairCxxLinkObjects(io: std.Io, allocator: std.mem.Allocator, tool_args: []const []const u8) !usize {
    if (!isCxxAssemblyCompatProject()) return 0;
    const project_dir = getenvSlice("ROSETTE_SHELL_PROJECT_DIR") orelse ".";
    var globals = try collectAsmGlobals(io, allocator, project_dir);
    defer globals.deinit(allocator);
    if (globals.items.len == 0) return 0;

    var repaired: usize = 0;
    for (tool_args) |arg| {
        if (!isObjectFile(arg)) continue;
        repaired += try weakenElfObjectSymbols(io, allocator, arg, globals.items, true);
    }
    return repaired;
}

fn weakenCompiledCxxObject(io: std.Io, allocator: std.mem.Allocator, object_path: []const u8) !usize {
    if (!isCxxAssemblyCompatProject()) return 0;
    const project_dir = getenvSlice("ROSETTE_SHELL_PROJECT_DIR") orelse ".";
    var globals = try collectAsmGlobals(io, allocator, project_dir);
    defer globals.deinit(allocator);
    if (globals.items.len == 0) return 0;
    return try weakenElfObjectSymbols(io, allocator, object_path, globals.items, true);
}

fn isCxxAssemblyCompatProject() bool {
    const kind = getenvSlice("ROSETTE_SHELL_PROJECT_KIND") orelse return false;
    return containsIgnoreCase(kind, "yasm-linux-elf64-cxx");
}

fn collectAsmGlobals(io: std.Io, allocator: std.mem.Allocator, project_dir: []const u8) !std.ArrayList([]const u8) {
    var globals: std.ArrayList([]const u8) = .empty;
    errdefer globals.deinit(allocator);

    var dir = std.Io.Dir.openDirAbsolute(io, project_dir, .{ .iterate = true }) catch return globals;
    defer dir.close(io);

    var it = dir.iterate();
    while (try it.next(io)) |entry| {
        if (!std.ascii.endsWithIgnoreCase(entry.name, ".asm")) continue;
        const path = try std.fs.path.join(allocator, &.{ project_dir, entry.name });
        const data = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(max_text_file)) catch continue;
        try appendAsmGlobalsFromSource(allocator, data, &globals);
    }
    return globals;
}

fn appendAsmGlobalsFromSource(allocator: std.mem.Allocator, source: []const u8, globals: *std.ArrayList([]const u8)) !void {
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |raw_line| {
        const comment_start = std.mem.indexOfScalar(u8, raw_line, ';') orelse raw_line.len;
        var line = std.mem.trim(u8, raw_line[0..comment_start], " \t\r\n");
        if (line.len >= 2 and line[0] == '[' and line[line.len - 1] == ']') {
            line = std.mem.trim(u8, line[1 .. line.len - 1], " \t\r\n");
        }
        if (!startsWithDirective(line, "global")) continue;

        var rest = std.mem.trim(u8, line["global".len..], " \t\r\n");
        while (rest.len != 0) {
            rest = trimAsmSeparators(rest);
            if (rest.len == 0) break;
            const end = asmSymbolEnd(rest);
            if (end == 0) break;
            const name = rest[0..end];
            if (!hasString(globals.items, name)) try globals.append(allocator, name);
            rest = rest[end..];
            if (rest.len != 0 and rest[0] == ':') {
                var suffix_end: usize = 1;
                while (suffix_end < rest.len and !isAsmSeparator(rest[suffix_end])) : (suffix_end += 1) {}
                rest = rest[suffix_end..];
            }
        }
    }
}

fn startsWithDirective(line: []const u8, directive: []const u8) bool {
    if (line.len < directive.len) return false;
    if (!std.ascii.eqlIgnoreCase(line[0..directive.len], directive)) return false;
    return line.len == directive.len or isAsmSeparator(line[directive.len]);
}

fn trimAsmSeparators(value: []const u8) []const u8 {
    var start: usize = 0;
    while (start < value.len and isAsmSeparator(value[start])) : (start += 1) {}
    return value[start..];
}

fn asmSymbolEnd(value: []const u8) usize {
    var end: usize = 0;
    while (end < value.len) : (end += 1) {
        const ch = value[end];
        if (isAsmSeparator(ch) or ch == ':') break;
    }
    return end;
}

fn isAsmSeparator(ch: u8) bool {
    return ch == ' ' or ch == '\t' or ch == ',' or ch == '\r' or ch == '\n';
}

fn weakenElfObjectSymbols(
    io: std.Io,
    allocator: std.mem.Allocator,
    object_path: []const u8,
    symbols: []const []const u8,
    require_main: bool,
) !usize {
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, object_path, allocator, .limited(64 * 1024 * 1024)) catch return 0;
    const changed = weakenElf64LittleSymbols(bytes, symbols, require_main) catch return 0;
    if (changed != 0) try writeFilePath(allocator, object_path, bytes);
    return changed;
}

fn weakenElf64LittleSymbols(bytes: []u8, symbols: []const []const u8, require_main: bool) !usize {
    if (bytes.len < 64) return 0;
    if (!std.mem.eql(u8, bytes[0..4], "\x7fELF")) return 0;
    if (bytes[4] != 2 or bytes[5] != 1) return 0;

    const shoff = readU64(bytes, 40) orelse return 0;
    const shentsize = readU16(bytes, 58) orelse return 0;
    const shnum = readU16(bytes, 60) orelse return 0;
    if (shentsize < 64) return 0;

    var has_main = !require_main;
    var sec_index: usize = 0;
    while (sec_index < shnum) : (sec_index += 1) {
        const section = readElfSection(bytes, shoff, shentsize, sec_index) orelse continue;
        if (section.section_type != 2) continue;
        const strtab_section = readElfSection(bytes, shoff, shentsize, section.link) orelse continue;
        const strtab = sliceRange(bytes, strtab_section.offset, strtab_section.size) orelse continue;
        var pos = section.offset;
        const end = section.offset + section.size;
        const entsize = if (section.entsize == 0) 24 else section.entsize;
        while (pos + 24 <= end and pos + 24 <= bytes.len) : (pos += entsize) {
            const shndx = readU16(bytes, pos + 6) orelse continue;
            if (shndx == 0) continue;
            const name_offset = readU32(bytes, pos) orelse continue;
            const name = elfString(strtab, name_offset) orelse continue;
            if (std.mem.eql(u8, name, "main")) has_main = true;
        }
    }
    if (!has_main) return 0;

    var changed: usize = 0;
    sec_index = 0;
    while (sec_index < shnum) : (sec_index += 1) {
        const section = readElfSection(bytes, shoff, shentsize, sec_index) orelse continue;
        if (section.section_type != 2) continue;
        const strtab_section = readElfSection(bytes, shoff, shentsize, section.link) orelse continue;
        const strtab = sliceRange(bytes, strtab_section.offset, strtab_section.size) orelse continue;
        var pos = section.offset;
        const end = section.offset + section.size;
        const entsize = if (section.entsize == 0) 24 else section.entsize;
        while (pos + 24 <= end and pos + 24 <= bytes.len) : (pos += entsize) {
            const shndx = readU16(bytes, pos + 6) orelse continue;
            if (shndx == 0) continue;
            const info = bytes[pos + 4];
            const binding = info >> 4;
            if (binding != 1) continue;
            const name_offset = readU32(bytes, pos) orelse continue;
            const name = elfString(strtab, name_offset) orelse continue;
            if (std.mem.eql(u8, name, "main")) continue;
            if (!hasString(symbols, name)) continue;
            bytes[pos + 4] = (2 << 4) | (info & 0x0f);
            changed += 1;
        }
    }
    return changed;
}

fn readElfSection(bytes: []const u8, shoff: u64, shentsize: u16, index: usize) ?ElfSection {
    const base_u64 = shoff + @as(u64, shentsize) * @as(u64, @intCast(index));
    if (base_u64 > std.math.maxInt(usize)) return null;
    const base: usize = @intCast(base_u64);
    if (base + 64 > bytes.len) return null;
    const offset_u64 = readU64(bytes, base + 24) orelse return null;
    const size_u64 = readU64(bytes, base + 32) orelse return null;
    const entsize_u64 = readU64(bytes, base + 56) orelse return null;
    if (offset_u64 > std.math.maxInt(usize) or size_u64 > std.math.maxInt(usize) or entsize_u64 > std.math.maxInt(usize)) return null;
    return .{
        .section_type = readU32(bytes, base + 4) orelse return null,
        .offset = @intCast(offset_u64),
        .size = @intCast(size_u64),
        .link = readU32(bytes, base + 40) orelse return null,
        .entsize = @intCast(entsize_u64),
    };
}

fn sliceRange(bytes: []const u8, offset: usize, size: usize) ?[]const u8 {
    if (offset > bytes.len or size > bytes.len - offset) return null;
    return bytes[offset .. offset + size];
}

fn elfString(strtab: []const u8, offset: u32) ?[]const u8 {
    const start: usize = offset;
    if (start >= strtab.len) return null;
    var end = start;
    while (end < strtab.len and strtab[end] != 0) : (end += 1) {}
    return strtab[start..end];
}

fn readU16(bytes: []const u8, offset: usize) ?u16 {
    if (offset > bytes.len or 2 > bytes.len - offset) return null;
    return std.mem.readInt(u16, bytes[offset..][0..2], .little);
}

fn readU32(bytes: []const u8, offset: usize) ?u32 {
    if (offset > bytes.len or 4 > bytes.len - offset) return null;
    return std.mem.readInt(u32, bytes[offset..][0..4], .little);
}

fn readU64(bytes: []const u8, offset: usize) ?u64 {
    if (offset > bytes.len or 8 > bytes.len - offset) return null;
    return std.mem.readInt(u64, bytes[offset..][0..8], .little);
}

fn hasString(values: []const []const u8, needle: []const u8) bool {
    for (values) |value| {
        if (std.mem.eql(u8, value, needle)) return true;
    }
    return false;
}

fn appendFilteredLinuxArgs(
    argv: *std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
    tool_args: []const []const u8,
    strip_ld_debug: bool,
) !void {
    var i: usize = 0;
    while (i < tool_args.len) : (i += 1) {
        const arg = tool_args[i];
        if (strip_ld_debug and std.mem.eql(u8, arg, "-g")) continue;
        if (std.mem.eql(u8, arg, "-z") and i + 1 < tool_args.len and std.mem.eql(u8, tool_args[i + 1], "noexecstack")) {
            i += 1;
            continue;
        }
        try argv.append(allocator, arg);
    }
}

fn execResolved(io: std.Io, allocator: std.mem.Allocator, tool_name: []const u8, tool_args: []const []const u8) !void {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);
    try argv.append(allocator, try resolveToolPath(allocator, tool_name));
    for (tool_args) |arg| try argv.append(allocator, arg);
    try execArgv(io, argv.items);
}

fn execArgv(io: std.Io, argv: []const []const u8) !void {
    const code = try runArgvResult(io, argv);
    std.process.exit(code);
}

fn runArgvResult(io: std.Io, argv: []const []const u8) !u8 {
    var child = std.process.spawn(io, .{
        .argv = argv,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    }) catch |err| {
        std.debug.print("rosette-shell: failed to spawn {s}: {s}\n", .{ argv[0], @errorName(err) });
        std.process.exit(127);
    };
    const term = child.wait(io) catch |err| {
        std.debug.print("rosette-shell: failed waiting for {s}: {s}\n", .{ argv[0], @errorName(err) });
        std.process.exit(127);
    };
    return switch (term) {
        .exited => |code| code,
        .signal => |sig| 128 + @as(u8, @intCast(@intFromEnum(sig))),
        .stopped => 128,
        .unknown => 1,
    };
}

fn resolveToolPath(allocator: std.mem.Allocator, tool_name: []const u8) ![]const u8 {
    if (std.mem.indexOfScalar(u8, tool_name, '/') != null) return tool_name;
    const search_path = getenvSlice("ROSETTE_SHELL_ORIGINAL_PATH") orelse getenvSlice("PATH") orelse "";
    const wrapper_dir = getenvSlice("ROSETTE_SHELL_WRAPPER_DIR") orelse "";

    var it = std.mem.splitScalar(u8, search_path, ':');
    while (it.next()) |dir| {
        if (dir.len == 0) continue;
        if (wrapper_dir.len != 0 and std.mem.eql(u8, dir, wrapper_dir)) continue;
        const candidate = try std.fs.path.join(allocator, &.{ dir, tool_name });
        if (canExecute(allocator, candidate)) return candidate;
    }
    return tool_name;
}

fn isCxxTool(tool_name: []const u8) bool {
    return std.mem.eql(u8, tool_name, "g++") or
        std.mem.eql(u8, tool_name, "c++") or
        std.mem.eql(u8, tool_name, "clang++");
}

fn isCcTool(tool_name: []const u8) bool {
    return std.mem.eql(u8, tool_name, "gcc") or
        std.mem.eql(u8, tool_name, "cc") or
        std.mem.eql(u8, tool_name, "clang");
}

fn appendExport(out: *std.ArrayList(u8), allocator: std.mem.Allocator, name: []const u8, value: []const u8) !void {
    try out.appendSlice(allocator, "export ");
    try out.appendSlice(allocator, name);
    try out.append(allocator, '=');
    try appendShellQuoted(out, allocator, value);
    try out.append(allocator, '\n');
}

fn appendShellQuoted(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: []const u8) !void {
    try out.append(allocator, '\'');
    for (value) |ch| {
        if (ch == '\'') {
            try out.appendSlice(allocator, "'\\''");
        } else {
            try out.append(allocator, ch);
        }
    }
    try out.append(allocator, '\'');
}

fn appendArgs(out: *std.ArrayList(u8), allocator: std.mem.Allocator, args: []const []const u8) !void {
    if (args.len == 0) {
        try out.appendSlice(allocator, "(default)");
        return;
    }
    for (args, 0..) |arg, i| {
        if (i != 0) try out.append(allocator, ' ');
        try appendShellQuoted(out, allocator, arg);
    }
}

fn appendInt(out: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u32) !void {
    const text = try std.fmt.allocPrint(allocator, "{d}", .{value});
    try out.appendSlice(allocator, text);
}

fn addSignal(signals: *std.ArrayList(u8), allocator: std.mem.Allocator, text: []const u8) !void {
    if (signals.items.len != 0) try signals.appendSlice(allocator, ",");
    try signals.appendSlice(allocator, text);
}

fn hasYasmElf64Makefile(makefile: []const u8) bool {
    return containsIgnoreCase(makefile, "yasm") and containsIgnoreCase(makefile, "elf64");
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;

    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        var matched = true;
        for (needle, 0..) |needle_ch, j| {
            if (std.ascii.toLower(haystack[i + j]) != std.ascii.toLower(needle_ch)) {
                matched = false;
                break;
            }
        }
        if (matched) return true;
    }
    return false;
}

fn getenvSlice(name: [:0]const u8) ?[]const u8 {
    const value = std.c.getenv(name) orelse return null;
    return std.mem.sliceTo(value, 0);
}

fn homeDir(allocator: std.mem.Allocator) ![]const u8 {
    if (getenvSlice("HOME")) |home| return try allocator.dupe(u8, home);
    return error.HomeNotSet;
}

fn absolutePath(allocator: std.mem.Allocator, raw_path: []const u8) ![]const u8 {
    const resolved = try std.fs.path.resolve(allocator, &.{raw_path});
    if (std.fs.path.isAbsolute(resolved)) return resolved;

    const cwd_buf = try allocator.alloc(u8, std.posix.PATH_MAX);
    defer allocator.free(cwd_buf);
    const cwd = std.c.realpath(".", cwd_buf.ptr) orelse return error.CwdResolveFailed;
    return try std.fs.path.resolve(allocator, &.{ std.mem.sliceTo(cwd, 0), resolved });
}

fn resolveAgainstProject(allocator: std.mem.Allocator, project_dir: []const u8, raw_path: []const u8) ![]const u8 {
    if (std.fs.path.isAbsolute(raw_path)) return try std.fs.path.resolve(allocator, &.{raw_path});
    return try std.fs.path.resolve(allocator, &.{ project_dir, raw_path });
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

fn writeFilePath(allocator: std.mem.Allocator, path: []const u8, data: []const u8) !void {
    const parent = std.fs.path.dirname(path);
    if (parent) |dir| try makePathRecursive(allocator, dir);
    const path_z = try allocator.dupeZ(u8, path);
    const fp = c.fopen(path_z.ptr, "wb");
    if (fp == null) return error.FileWriteFailed;
    defer _ = c.fclose(fp);

    if (data.len != 0) {
        const wrote = c.fwrite(data.ptr, 1, data.len, fp);
        if (wrote != data.len) return error.FileWriteFailed;
    }
}

fn appendFilePath(allocator: std.mem.Allocator, path: []const u8, data: []const u8) !void {
    const parent = std.fs.path.dirname(path);
    if (parent) |dir| try makePathRecursive(allocator, dir);
    const path_z = try allocator.dupeZ(u8, path);
    const fp = c.fopen(path_z.ptr, "ab");
    if (fp == null) return error.FileWriteFailed;
    defer _ = c.fclose(fp);

    if (data.len != 0) {
        const wrote = c.fwrite(data.ptr, 1, data.len, fp);
        if (wrote != data.len) return error.FileWriteFailed;
    }
}

fn chmodPath(allocator: std.mem.Allocator, path: []const u8, mode: u16) !void {
    const path_z = try allocator.dupeZ(u8, path);
    if (c.chmod(path_z.ptr, mode) != 0) return error.ChmodFailed;
}

fn resolveOnPath(allocator: std.mem.Allocator, name: []const u8) ?[]const u8 {
    const path = getenvSlice("PATH") orelse return null;
    var it = std.mem.splitScalar(u8, path, ':');
    while (it.next()) |dir| {
        if (dir.len == 0) continue;
        const candidate = std.fs.path.join(allocator, &.{ dir, name }) catch continue;
        if (canExecute(allocator, candidate)) return candidate;
    }
    return null;
}

fn installDylib(init: std.process.Init, allocator: std.mem.Allocator, source_root: []const u8, dylib_path: []const u8) !void {
    const candidates = [_][]const u8{
        try std.fs.path.join(allocator, &.{ source_root, "zig-out", "lib", "rosette-exec.dylib" }),
        try std.fs.path.join(allocator, &.{ source_root, "..", "..", "MacOS", "rosette-exec.dylib" }),
    };

    for (candidates) |candidate| {
        if (fileExists(allocator, candidate)) {
            try copyFile(init, allocator, candidate, dylib_path, "rosette-exec.dylib");
            _ = chmodPath(allocator, dylib_path, 0o755) catch {};
            return;
        }
    }

    const source_path = try std.fs.path.join(allocator, &.{ source_root, "src", "shell", "dyld", "rosette-exec.c" });
    if (!fileExists(allocator, source_path)) {
        std.debug.print("rosette-shell: warning: rosette-exec.c not found below {s}\n", .{source_root});
        return;
    }
    try compileDylibFromSource(init, allocator, source_path, dylib_path);
}

fn compileDylibFromSource(init: std.process.Init, allocator: std.mem.Allocator, source_path: []const u8, dylib_path: []const u8) !void {
    const zig_path = resolveOnPath(allocator, "zig") orelse {
        std.debug.print("rosette-shell: warning: zig not found on PATH, skipping dylib compilation\n", .{});
        std.debug.print("  elf_processor binary installed, DYLD interposition dylib not compiled\n", .{});
        return;
    };

    const tmp = getenvSlice("TMPDIR") orelse "/tmp";
    const local_cache = try std.fs.path.join(allocator, &.{ tmp, "rosette-zig-cache" });
    const global_cache = try std.fs.path.join(allocator, &.{ tmp, "rosette-zig-global-cache" });
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);

    try argv.append(allocator, zig_path);
    try argv.append(allocator, "cc");
    try argv.append(allocator, "--cache-dir");
    try argv.append(allocator, local_cache);
    try argv.append(allocator, "--global-cache-dir");
    try argv.append(allocator, global_cache);
    try argv.append(allocator, "-dynamiclib");
    try argv.append(allocator, "-arch");
    try argv.append(allocator, "arm64");
    try argv.append(allocator, "-o");
    try argv.append(allocator, dylib_path);
    try argv.append(allocator, source_path);
    try argv.append(allocator, "-install_name");
    try argv.append(allocator, "@rpath/rosette-exec.dylib");

    const code = runArgvResult(init.io, argv.items) catch |err| {
        std.debug.print("rosette-shell: warning: failed to compile rosette-exec.dylib: {s}\n", .{@errorName(err)});
        std.debug.print("  elf_processor binary installed, DYLD interposition not available\n", .{});
        return;
    };
    if (code != 0) {
        std.debug.print("rosette-shell: warning: zig cc returned exit code {d} for dylib compilation\n", .{code});
        std.debug.print("  elf_processor binary installed, DYLD interposition not available\n", .{});
        return;
    }

    _ = chmodPath(allocator, dylib_path, 0o755) catch {};
    std.debug.print("  compiled rosette-exec.dylib\n", .{});
}

fn copyElfProcessor(init: std.process.Init, allocator: std.mem.Allocator, source_root: []const u8, dest_path: []const u8) !void {
    const candidates = [_][]const u8{
        try std.fs.path.join(allocator, &.{ source_root, "zig-out", "bin", "elf_processor" }),
        try std.fs.path.join(allocator, &.{ source_root, "..", "..", "MacOS", "elf_processor" }),
        try std.fs.path.join(allocator, &.{ source_root, "elf_processor" }),
    };

    for (candidates) |candidate| {
        if (fileExists(allocator, candidate) and canExecute(allocator, candidate)) {
            try copyFile(init, allocator, candidate, dest_path, "elf_processor");
            _ = chmodPath(allocator, dest_path, 0o755) catch {};
            return;
        }
    }
    std.debug.print("rosette-shell: warning: elf_processor binary not found; build with 'zig build' first\n", .{});
}

fn copyCompatRouter(init: std.process.Init, allocator: std.mem.Allocator, source_root: []const u8, dest_path: []const u8) !void {
    const candidates = [_][]const u8{
        try std.fs.path.join(allocator, &.{ source_root, "zig-out", "bin", "rosette-router" }),
        try std.fs.path.join(allocator, &.{ source_root, "..", "..", "MacOS", "rosette-router" }),
        try std.fs.path.join(allocator, &.{ source_root, "rosette-router" }),
    };

    for (candidates) |candidate| {
        if (fileExists(allocator, candidate) and canExecute(allocator, candidate)) {
            try copyFile(init, allocator, candidate, dest_path, "rosette-router");
            _ = chmodPath(allocator, dest_path, 0o755) catch {};
            return;
        }
    }
    std.debug.print("rosette-shell: warning: rosette-router binary not found; build with 'make compat-router-build' first\n", .{});
}

fn copyFile(init: std.process.Init, allocator: std.mem.Allocator, source_path: []const u8, dest_path: []const u8, label: []const u8) !void {
    const bytes = std.Io.Dir.cwd().readFileAlloc(init.io, source_path, allocator, .unlimited) catch {
        std.debug.print("rosette-shell: warning: could not read {s} from {s}\n", .{ label, source_path });
        return;
    };
    writeFilePath(allocator, dest_path, bytes) catch {
        std.debug.print("rosette-shell: warning: could not write {s} to {s}\n", .{ label, dest_path });
        return;
    };
    std.debug.print("  installed {s}\n", .{label});
}

fn unlinkIfExists(allocator: std.mem.Allocator, path: []const u8) !void {
    const path_z = try allocator.dupeZ(u8, path);
    if (c.unlink(path_z.ptr) != 0 and c.access(path_z.ptr, 0) == 0) return error.UnlinkFailed;
}

fn rmdirIfEmpty(allocator: std.mem.Allocator, path: []const u8) !void {
    const path_z = try allocator.dupeZ(u8, path);
    if (c.rmdir(path_z.ptr) != 0 and c.access(path_z.ptr, 0) == 0) return error.RmdirFailed;
}

fn fileExists(allocator: std.mem.Allocator, path: []const u8) bool {
    const path_z = allocator.dupeZ(u8, path) catch return false;
    return c.access(path_z.ptr, 0) == 0;
}

fn canExecute(allocator: std.mem.Allocator, path: []const u8) bool {
    const path_z = allocator.dupeZ(u8, path) catch return false;
    return c.access(path_z.ptr, 1) == 0;
}

test "YASM invocation parser derives default ELF64 object" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const args = [_][]const u8{ "-g", "dwarf2", "-f", "elf64", "ast01.asm", "-l", "ast01.lst" };
    const invocation = try parseYasmInvocation(arena.allocator(), &args);
    try std.testing.expect(invocation.isElf64());
    try std.testing.expectEqualStrings("ast01.asm", invocation.source_path.?);
    try std.testing.expectEqualStrings("ast01.o", invocation.artifact_path.?);
}

test "YASM invocation parser handles explicit object and compact format" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const args = [_][]const u8{ "-felf64", "-o", "build/out.o", "src/main.asm" };
    const invocation = try parseYasmInvocation(arena.allocator(), &args);
    try std.testing.expect(invocation.isElf64());
    try std.testing.expectEqualStrings("src/main.asm", invocation.source_path.?);
    try std.testing.expectEqualStrings("build/out.o", invocation.artifact_path.?);
}

test "Makefile detector accepts reordered YASM ELF64 flags" {
    const makefile =
        \\ASM = yasm -f elf64 -g dwarf2
        \\main.o: main.asm
        \\    $(ASM) main.asm -l main.lst
    ;
    try std.testing.expect(hasYasmElf64Makefile(makefile));
}

test "shell config parser accepts TOML and uppercase aliases" {
    const toml =
        \\[graphics]
        \\enabled = false
        \\
        \\[elf]
        \\dump_results = "auto"
        \\dump_all_results = false
        \\
        \\GRAPHICS = "ON"
        \\ROSETTE_ELF_DUMP_RESULTS = "ON"
    ;
    const config = parseShellConfig(toml);
    try std.testing.expect(config.graphics_enabled);
    try std.testing.expectEqual(ConfigMode.on, config.elf_dump_results);
    try std.testing.expect(!config.elf_dump_all_results);
}

test "auto result dump triggers for detected yasm elf64 run targets" {
    const config = ShellConfig{ .elf_dump_results = .auto };
    const detected = Detection{
        .detected = true,
        .score = 8,
        .kind = "yasm-linux-elf64",
        .signals = "makefile:yasm-elf64,asm:text-section,asm:globals",
    };
    const run_args = [_][]const u8{"run"};
    const build_args = [_][]const u8{};
    try std.testing.expect(shouldEnableResultDump(config, detected, &run_args));
    try std.testing.expect(!shouldEnableResultDump(config, detected, &build_args));
}

test "direct ELF result dump triggers for detected yasm elf64 projects" {
    const config = ShellConfig{ .elf_dump_results = .auto };
    const detected = Detection{
        .detected = true,
        .score = 8,
        .kind = "yasm-linux-elf64",
        .signals = "makefile:yasm-elf64,asm:text-section,asm:globals",
    };
    const generic = Detection{
        .detected = false,
        .score = 2,
        .kind = "unknown",
        .signals = "none",
    };
    try std.testing.expect(shouldEnableDirectResultDump(config, detected));
    try std.testing.expect(!shouldEnableDirectResultDump(config, generic));
}

test "shell snippet includes zsh direct ELF launcher" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const snippet = try buildShellSnippet(
        arena.allocator(),
        "/tmp/rosette/bin/rosette-shell",
        "/tmp/rosette/lib/rosette-exec.dylib",
        "/tmp/rosette/bin/elf_processor",
    );
    try std.testing.expect(containsIgnoreCase(snippet, "run-elf"));
    try std.testing.expect(containsIgnoreCase(snippet, "__rosette_refresh_elf_commands"));
    try std.testing.expect(containsIgnoreCase(snippet, "detect \"$PWD\""));
    try std.testing.expect(containsIgnoreCase(snippet, "functions[$__rosette_cmd]"));
    try std.testing.expect(containsIgnoreCase(snippet, "ROSETTE_ENABLE_DYLD_INTERPOSE:-0"));
    try std.testing.expect(containsIgnoreCase(snippet, "__rosette_strip_dyld_interposer"));
}

test "assembly global parser handles lists and bracket directives" {
    var globals: std.ArrayList([]const u8) = .empty;
    defer globals.deinit(std.testing.allocator);
    const source =
        \\global checkParams, getWord:function, printWord
        \\[global closeFile]
        \\global checkParams ; duplicate should be ignored
    ;
    try appendAsmGlobalsFromSource(std.testing.allocator, source, &globals);
    try std.testing.expectEqual(@as(usize, 4), globals.items.len);
    try std.testing.expect(hasString(globals.items, "checkParams"));
    try std.testing.expect(hasString(globals.items, "getWord"));
    try std.testing.expect(hasString(globals.items, "printWord"));
    try std.testing.expect(hasString(globals.items, "closeFile"));
}

test "ELF weakener demotes only colliding C++ placeholders" {
    var bytes = [_]u8{0} ** 512;
    bytes[0] = 0x7f;
    bytes[1] = 'E';
    bytes[2] = 'L';
    bytes[3] = 'F';
    bytes[4] = 2;
    bytes[5] = 1;
    bytes[6] = 1;
    std.mem.writeInt(u64, bytes[40..48], 64, .little);
    std.mem.writeInt(u16, bytes[58..60], 64, .little);
    std.mem.writeInt(u16, bytes[60..62], 4, .little);

    const symtab_sh = 64 + 64;
    std.mem.writeInt(u32, bytes[symtab_sh + 4 ..][0..4], 2, .little);
    std.mem.writeInt(u64, bytes[symtab_sh + 24 ..][0..8], 320, .little);
    std.mem.writeInt(u64, bytes[symtab_sh + 32 ..][0..8], 72, .little);
    std.mem.writeInt(u32, bytes[symtab_sh + 40 ..][0..4], 2, .little);
    std.mem.writeInt(u64, bytes[symtab_sh + 56 ..][0..8], 24, .little);

    const strtab_sh = 64 + 128;
    std.mem.writeInt(u32, bytes[strtab_sh + 4 ..][0..4], 3, .little);
    std.mem.writeInt(u64, bytes[strtab_sh + 24 ..][0..8], 400, .little);
    std.mem.writeInt(u64, bytes[strtab_sh + 32 ..][0..8], 27, .little);

    const names = "\x00main\x00checkParams\x00getWord\x00";
    @memcpy(bytes[400 .. 400 + names.len], names);

    const main_sym = 320 + 24;
    std.mem.writeInt(u32, bytes[main_sym..][0..4], 1, .little);
    bytes[main_sym + 4] = 0x12;
    std.mem.writeInt(u16, bytes[main_sym + 6 ..][0..2], 1, .little);

    const placeholder_sym = 320 + 48;
    std.mem.writeInt(u32, bytes[placeholder_sym..][0..4], 6, .little);
    bytes[placeholder_sym + 4] = 0x12;
    std.mem.writeInt(u16, bytes[placeholder_sym + 6 ..][0..2], 1, .little);

    const symbols = [_][]const u8{"checkParams"};
    const changed = try weakenElf64LittleSymbols(bytes[0..], &symbols, true);
    try std.testing.expectEqual(@as(usize, 1), changed);
    try std.testing.expectEqual(@as(u8, 0x12), bytes[main_sym + 4]);
    try std.testing.expectEqual(@as(u8, 0x22), bytes[placeholder_sym + 4]);
}
