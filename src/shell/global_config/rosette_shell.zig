const std = @import("std");
const builtin = @import("builtin");
const process_guard = @import("entrypoint_kernel_process_guard");
const project_includes = @import("compat_source_include_compat");
const pid_manager = @import("pid_manager.zig");

const c = @cImport({
    @cInclude("errno.h");
    @cInclude("libproc.h");
    @cInclude("signal.h");
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("string.h");
    @cInclude("sys/stat.h");
    @cInclude("sys/sysctl.h");
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
    \\# Strict is for diagnostics: Rosette must own the route, and fallback or
    \\# unsupported routes abort loudly instead of quietly using Apple Rosetta 2.
    \\strict = false
    \\abort_on_fallback = false
    \\abort_on_unsupported = false
    \\trace = true
    \\
;

const compat_config_upgrade_text =
    \\# Apple Rosetta 2 remains a traced fallback while Rosette's Mach-O
    \\# x86_64 backend is being brought up.
    \\allow_rosetta2_fallback = true
    \\# Strict is for diagnostics: Rosette must own the route, and fallback or
    \\# unsupported routes abort loudly instead of quietly using Apple Rosetta 2.
    \\strict = false
    \\abort_on_fallback = false
    \\abort_on_unsupported = false
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
        try cleanState(init, allocator, args[2..]);
        return;
    }
    if (std.mem.eql(u8, args[1], "route-arch")) {
        try routeArch(init, allocator, args[2..]);
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
    if (std.mem.eql(u8, args[1], "compiler-sanitize")) {
        if (args.len < 3) return usage(args[0]);
        try runCompilerSanitizer(init.io, allocator, args[2..]);
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
        \\  rosette-clean-state [--scan|--dry-run] [--no-xenia|--xenia]
        \\  {s} route-arch <arch-args...>
        \\  {s} route run [options] <target|Application.app> [-- target-args...]
        \\  {s} run-elf <x86-64-elf-path> [args...]
        \\  {s} tool <tool-name> [tool-args...]
        \\  {s} compiler-sanitize <compiler> [compiler-args...]
        \\  {s} recipe-shell [sh-args...]
        \\  {s} is-elf64 <path>
        \\
        \\Common config at ~/.rosette/config.toml:
        \\  [elf]
        \\  dump_results = "auto"  # off | on | auto
        \\  dump_all_results = false
        \\  [graphics]
        \\  enabled = false
        \\  [compat]
        \\  allow_rosetta2_fallback = true
        \\  strict = false
        \\  abort_on_fallback = false
        \\  abort_on_unsupported = false
        \\
    , .{ exe_name, exe_name, exe_name, exe_name, exe_name, exe_name, exe_name, exe_name, exe_name, exe_name, exe_name, exe_name, exe_name, exe_name, exe_name, exe_name, exe_name });
}

fn installOrUpdate(init: std.process.Init, allocator: std.mem.Allocator, source_root: []const u8) !void {
    std.debug.print("[INSTALL] Starting Rosette shell installation/update\n", .{});

    // Check for existing installation stamp
    const home = homeDir(allocator) catch |err| {
        std.debug.print("[INSTALL] CRITICAL ERROR: Failed to get home directory: {s}\n", .{@errorName(err)});
        return err;
    };
    const rosette_dir = std.fs.path.join(allocator, &.{ home, ".rosette" }) catch |err| {
        std.debug.print("[INSTALL] ERROR: Failed to build rosette_dir path: {s}\n", .{@errorName(err)});
        return err;
    };
    const stamp_path = std.fs.path.join(allocator, &.{ rosette_dir, ".install-stamp" }) catch unreachable;

    if (fileExists(allocator, stamp_path)) {
        const contents = std.Io.Dir.cwd().readFileAlloc(init.io, stamp_path, allocator, .limited(256)) catch "";
        if (contents.len > 0) {
            std.debug.print("[INSTALL] Found existing installation stamp\n", .{});
            std.debug.print("[INSTALL] Previous installation info: {s}\n", .{contents});
            std.debug.print("[INSTALL] Continuing with update (will overwrite existing installation)\n", .{});
        }
    }

    std.debug.print("[INSTALL] Pre-flight cleanup: skipped during install/update; use rosette-clean-state explicitly for stale helpers\n", .{});

    std.debug.print("[INSTALL] Step 1: Building directory paths\n", .{});
    const bin_dir = std.fs.path.join(allocator, &.{ rosette_dir, "bin" }) catch |err| {
        std.debug.print("[INSTALL] ERROR: Failed to build bin_dir path: {s}\n", .{@errorName(err)});
        return err;
    };
    const lib_dir = std.fs.path.join(allocator, &.{ rosette_dir, "lib" }) catch |err| {
        std.debug.print("[INSTALL] ERROR: Failed to build lib_dir path: {s}\n", .{@errorName(err)});
        return err;
    };
    const wrapper_dir = std.fs.path.join(allocator, &.{ rosette_dir, "wrappers" }) catch |err| {
        std.debug.print("[INSTALL] ERROR: Failed to build wrapper_dir path: {s}\n", .{@errorName(err)});
        return err;
    };
    const helper_path = std.fs.path.join(allocator, &.{ bin_dir, "rosette-shell" }) catch |err| {
        std.debug.print("[INSTALL] ERROR: Failed to build helper_path: {s}\n", .{@errorName(err)});
        return err;
    };
    const rosette_path = std.fs.path.join(allocator, &.{ bin_dir, "rosette" }) catch |err| {
        std.debug.print("[INSTALL] ERROR: Failed to build rosette_path: {s}\n", .{@errorName(err)});
        return err;
    };
    const arch_wrapper_path = std.fs.path.join(allocator, &.{ bin_dir, "arch" }) catch |err| {
        std.debug.print("[INSTALL] ERROR: Failed to build arch_wrapper_path: {s}\n", .{@errorName(err)});
        return err;
    };
    const arch_backend_path = std.fs.path.join(allocator, &.{ bin_dir, "rosette-arch" }) catch |err| {
        std.debug.print("[INSTALL] ERROR: Failed to build arch_backend_path: {s}\n", .{@errorName(err)});
        return err;
    };
    const compiler_launcher_path = std.fs.path.join(allocator, &.{ bin_dir, "rosette-compiler-sanitize" }) catch |err| {
        std.debug.print("[INSTALL] ERROR: Failed to build compiler_launcher_path: {s}\n", .{@errorName(err)});
        return err;
    };
    const clean_state_path = std.fs.path.join(allocator, &.{ bin_dir, "rosette-clean-state" }) catch |err| {
        std.debug.print("[INSTALL] ERROR: Failed to build clean_state_path: {s}\n", .{@errorName(err)});
        return err;
    };
    const shell_path = std.fs.path.join(allocator, &.{ rosette_dir, "rosette-shell.sh" }) catch |err| {
        std.debug.print("[INSTALL] ERROR: Failed to build shell_path: {s}\n", .{@errorName(err)});
        return err;
    };
    const bash_env_path = std.fs.path.join(allocator, &.{ rosette_dir, "rosette-bash-env.sh" }) catch |err| {
        std.debug.print("[INSTALL] ERROR: Failed to build bash_env_path: {s}\n", .{@errorName(err)});
        return err;
    };
    const toml_path = std.fs.path.join(allocator, &.{ rosette_dir, "config.toml" }) catch |err| {
        std.debug.print("[INSTALL] ERROR: Failed to build toml_path: {s}\n", .{@errorName(err)});
        return err;
    };
    const compat_router_path = std.fs.path.join(allocator, &.{ bin_dir, "rosette-router" }) catch |err| {
        std.debug.print("[INSTALL] ERROR: Failed to build compat_router_path: {s}\n", .{@errorName(err)});
        return err;
    };
    const macho_processor_path = std.fs.path.join(allocator, &.{ bin_dir, "macho_processor" }) catch |err| {
        std.debug.print("[INSTALL] ERROR: Failed to build macho_processor_path: {s}\n", .{@errorName(err)});
        return err;
    };

    std.debug.print("[INSTALL] Step 2: Creating directory structure\n", .{});
    const include_dir = std.fs.path.join(allocator, &.{ rosette_dir, "include" }) catch |err| {
        std.debug.print("[INSTALL] ERROR: Failed to build include_dir: {s}\n", .{@errorName(err)});
        return err;
    };
    makePathRecursive(allocator, bin_dir) catch |err| {
        std.debug.print("[INSTALL] ERROR: Failed to create bin_dir: {s}\n", .{@errorName(err)});
        return err;
    };
    std.debug.print("[INSTALL] Created bin_dir: {s}\n", .{bin_dir});
    makePathRecursive(allocator, wrapper_dir) catch |err| {
        std.debug.print("[INSTALL] WARNING: Failed to create wrapper_dir: {s}\n", .{@errorName(err)});
        std.debug.print("[INSTALL] Wrappers will not be installed\n", .{});
    };
    std.debug.print("[INSTALL] Created wrapper_dir: {s}\n", .{wrapper_dir});
    makePathRecursive(allocator, lib_dir) catch |err| {
        std.debug.print("[INSTALL] ERROR: Failed to create lib_dir: {s}\n", .{@errorName(err)});
        return err;
    };
    std.debug.print("[INSTALL] Created lib_dir: {s}\n", .{lib_dir});
    makePathRecursive(allocator, include_dir) catch |err| {
        std.debug.print("[INSTALL] WARNING: Failed to create include_dir: {s}\n", .{@errorName(err)});
        std.debug.print("[INSTALL] Compatibility headers will not be installed\n", .{});
    };
    std.debug.print("[INSTALL] Created include_dir: {s}\n", .{include_dir});

    std.debug.print("[INSTALL] Step 3: Installing compiler compatibility headers\n", .{});
    ensureX86CompatHeader(allocator, include_dir) catch |err| {
        std.debug.print("[INSTALL] WARNING: Failed to install x86 compatibility header: {s}\n", .{@errorName(err)});
    };
    ensureMacOSCompatHeaders(init.io, allocator, include_dir) catch |err| {
        std.debug.print("[INSTALL] WARNING: Failed to install macOS compatibility headers: {s}\n", .{@errorName(err)});
    };

    std.debug.print("[INSTALL] Step 4: Copying helper binaries\n", .{});
    copySelf(init, allocator, helper_path) catch |err| {
        std.debug.print("[INSTALL] ERROR: Failed to copy rosette-shell: {s}\n", .{@errorName(err)});
        return err;
    };
    std.debug.print("[INSTALL] Copied rosette-shell to: {s}\n", .{helper_path});
    copySelf(init, allocator, rosette_path) catch |err| {
        std.debug.print("[INSTALL] WARNING: Failed to copy rosette: {s}\n", .{@errorName(err)});
    };
    std.debug.print("[INSTALL] Copied rosette to: {s}\n", .{rosette_path});

    std.debug.print("[INSTALL] Step 5: Installing arch backend\n", .{});
    ensureArchBackend(allocator, arch_backend_path) catch |err| {
        std.debug.print("[INSTALL] WARNING: Failed to install arch backend: {s}\n", .{@errorName(err)});
    };
    std.debug.print("[INSTALL] Installed arch backend: {s}\n", .{arch_backend_path});
    ensureArchWrapper(allocator, arch_wrapper_path, arch_backend_path) catch |err| {
        std.debug.print("[INSTALL] WARNING: Failed to install arch wrapper: {s}\n", .{@errorName(err)});
    };
    std.debug.print("[INSTALL] Installed arch wrapper: {s}\n", .{arch_wrapper_path});

    std.debug.print("[INSTALL] Step 6: Installing compiler launcher\n", .{});
    ensureCompilerLauncher(allocator, compiler_launcher_path, helper_path) catch |err| {
        std.debug.print("[INSTALL] WARNING: Failed to install compiler launcher: {s}\n", .{@errorName(err)});
    };
    std.debug.print("[INSTALL] Installed compiler launcher: {s}\n", .{compiler_launcher_path});

    std.debug.print("[INSTALL] Step 7: Installing clean state backend\n", .{});
    ensureCleanStateBackend(allocator, clean_state_path) catch |err| {
        std.debug.print("[INSTALL] WARNING: Failed to install clean state backend: {s}\n", .{@errorName(err)});
    };
    std.debug.print("[INSTALL] Installed clean state backend: {s}\n", .{clean_state_path});

    std.debug.print("[INSTALL] Step 8: Installing tool wrappers\n", .{});
    ensureWrappers(allocator, wrapper_dir, helper_path) catch |err| {
        std.debug.print("[INSTALL] WARNING: Failed to install tool wrappers: {s}\n", .{@errorName(err)});
    };
    std.debug.print("[INSTALL] Installed wrappers in: {s}\n", .{wrapper_dir});

    std.debug.print("[INSTALL] Step 9: Ensuring config file\n", .{});
    ensureConfigFile(init.io, allocator, toml_path) catch |err| {
        std.debug.print("[INSTALL] WARNING: Failed to ensure config file: {s}\n", .{@errorName(err)});
    };
    std.debug.print("[INSTALL] Config file: {s}\n", .{toml_path});

    const elf_processor_path = std.fs.path.join(allocator, &.{ bin_dir, "elf_processor" }) catch |err| {
        std.debug.print("[INSTALL] ERROR: Failed to build elf_processor_path: {s}\n", .{@errorName(err)});
        return err;
    };
    const dyld_lib_path = std.fs.path.join(allocator, &.{ lib_dir, "rosette-exec.dylib" }) catch |err| {
        std.debug.print("[INSTALL] ERROR: Failed to build dyld_lib_path: {s}\n", .{@errorName(err)});
        return err;
    };
    const is_macos = comptime builtin.target.os.tag == .macos;

    if (source_root.len != 0) {
        std.debug.print("[INSTALL] Step 10: Copying processors from source root: {s}\n", .{source_root});
        copyElfProcessor(init, allocator, source_root, elf_processor_path) catch |err| {
            std.debug.print("[INSTALL] WARNING: Failed to copy ELF processor: {s}\n", .{@errorName(err)});
        };
        std.debug.print("[INSTALL] Copied ELF processor to: {s}\n", .{elf_processor_path});
        copyCompatRouter(init, allocator, source_root, compat_router_path) catch |err| {
            std.debug.print("[INSTALL] WARNING: Failed to copy compat router: {s}\n", .{@errorName(err)});
        };
        std.debug.print("[INSTALL] Copied compat router to: {s}\n", .{compat_router_path});
        copyMachoProcessor(init, allocator, source_root, macho_processor_path) catch |err| {
            std.debug.print("[INSTALL] WARNING: Failed to copy Mach-O processor: {s}\n", .{@errorName(err)});
        };
        std.debug.print("[INSTALL] Copied Mach-O processor to: {s}\n", .{macho_processor_path});

        if (is_macos) {
            std.debug.print("[INSTALL] Step 11: Compiling dylib (this may take a moment)\n", .{});
            installDylib(init, allocator, source_root, dyld_lib_path) catch |err| {
                std.debug.print("[INSTALL] WARNING: Failed to install dylib: {s}\n", .{@errorName(err)});
                std.debug.print("[INSTALL] DYLD interposition will not be available\n", .{});
            };
            std.debug.print("[INSTALL] Compiled dylib to: {s}\n", .{dyld_lib_path});
        }
    } else {
        std.debug.print("[INSTALL] Step 10-11: Skipped (no source_root provided)\n", .{});
    }

    if (source_root.len != 0) {
        const rosette_c_fix_path = std.fs.path.join(allocator, &.{ bin_dir, "rosette-c-fix" }) catch |err| {
            std.debug.print("[INSTALL] ERROR: Failed to build rosette-c-fix path: {s}\n", .{@errorName(err)});
            return err;
        };
        std.debug.print("[INSTALL] Step 11a: Installing rosette-c-fix binary\n", .{});
        copyRosetteCFix(init, allocator, source_root, rosette_c_fix_path) catch |err| {
            std.debug.print("[INSTALL] WARNING: Failed to install rosette-c-fix: {s}\n", .{@errorName(err)});
        };
        std.debug.print("[INSTALL] Installed rosette-c-fix: {s}\n", .{rosette_c_fix_path});
    }

    std.debug.print("[INSTALL] Step 12: Building shell snippet\n", .{});
    const snippet = buildShellSnippet(
        allocator,
        helper_path,
        if (is_macos and fileExists(allocator, dyld_lib_path)) dyld_lib_path else null,
        if (fileExists(allocator, elf_processor_path)) elf_processor_path else null,
    ) catch |err| {
        std.debug.print("[INSTALL] ERROR: Failed to build shell snippet: {s}\n", .{@errorName(err)});
        return err;
    };
    writeFilePath(allocator, shell_path, snippet) catch |err| {
        std.debug.print("[INSTALL] ERROR: Failed to write shell snippet: {s}\n", .{@errorName(err)});
        return err;
    };
    chmodPath(allocator, shell_path, 0o644) catch |err| {
        std.debug.print("[INSTALL] WARNING: Failed to chmod shell snippet: {s}\n", .{@errorName(err)});
    };
    std.debug.print("[INSTALL] Wrote shell snippet: {s}\n", .{shell_path});

    std.debug.print("[INSTALL] Step 13: Building bash env snippet\n", .{});
    const bash_env_snippet = buildBashEnvSnippet(allocator, helper_path) catch |err| {
        std.debug.print("[INSTALL] ERROR: Failed to build bash env snippet: {s}\n", .{@errorName(err)});
        return err;
    };
    writeFilePath(allocator, bash_env_path, bash_env_snippet) catch |err| {
        std.debug.print("[INSTALL] ERROR: Failed to write bash env snippet: {s}\n", .{@errorName(err)});
        return err;
    };
    chmodPath(allocator, bash_env_path, 0o644) catch |err| {
        std.debug.print("[INSTALL] WARNING: Failed to chmod bash env snippet: {s}\n", .{@errorName(err)});
    };
    std.debug.print("[INSTALL] Wrote bash env snippet: {s}\n", .{bash_env_path});

    std.debug.print("[INSTALL] Step 14: Installing profile blocks\n", .{});
    const block = buildProfileBlock(allocator) catch |err| {
        std.debug.print("[INSTALL] ERROR: Failed to build profile block: {s}\n", .{@errorName(err)});
        return err;
    };
    installProfileBlocks(init.io, allocator, home, block) catch |err| {
        std.debug.print("[INSTALL] WARNING: Failed to install profile blocks: {s}\n", .{@errorName(err)});
        std.debug.print("[INSTALL] You may need to manually source the shell script\n", .{});
    };
    std.debug.print("[INSTALL] Installed profile blocks in home: {s}\n", .{home});

    if (source_root.len != 0) {
        std.debug.print("[INSTALL] Step 15: Writing source-root config\n", .{});
        const config_path = std.fs.path.join(allocator, &.{ rosette_dir, "source-root" }) catch |err| {
            std.debug.print("[INSTALL] WARNING: Failed to build source-root config path: {s}\n", .{@errorName(err)});
            return;
        };
        const source_text = std.fmt.allocPrint(allocator, "{s}\n", .{source_root}) catch |err| {
            std.debug.print("[INSTALL] WARNING: Failed to format source-root: {s}\n", .{@errorName(err)});
            return;
        };
        writeFilePath(allocator, config_path, source_text) catch |err| {
            std.debug.print("[INSTALL] WARNING: Failed to write source-root config: {s}\n", .{@errorName(err)});
        };
        std.debug.print("[INSTALL] Wrote source-root: {s}\n", .{config_path});
    }

    std.debug.print("[INSTALL] Step 16: Printing installation summary\n", .{});
    std.debug.print("Rosette shell integration installed.\n", .{});
    std.debug.print("source: {s}\n", .{shell_path});
    std.debug.print("command: {s}\n", .{rosette_path});
    std.debug.print("arch_backend: {s}\n", .{arch_backend_path});
    std.debug.print("compiler_launcher: {s}\n", .{compiler_launcher_path});
    std.debug.print("clean_state: {s}\n", .{clean_state_path});
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
    if (fileExists(allocator, macho_processor_path)) {
        std.debug.print("macho_processor: {s}\n", .{macho_processor_path});
    } else {
        std.debug.print("macho_processor: missing; x86_64 Mach-O routing will stop at diagnostics\n", .{});
    }
    std.debug.print("current terminal reload: source ~/.rosette/rosette-shell.sh\n", .{});
    std.debug.print("diagnose from a project: rosette-diagnose-shell ./program\n", .{});

    // Write installation stamp
    const stamp_path_final = std.fs.path.join(allocator, &.{ rosette_dir, ".install-stamp" }) catch unreachable;
    const timestamp = c.time(null);
    const source_info = if (source_root.len > 0)
        try std.fmt.allocPrint(allocator, "source={s} ", .{source_root})
    else
        try allocator.dupe(u8, "");
    const stamp_content = try std.fmt.allocPrint(allocator, "{s}timestamp={d}\n", .{ source_info, timestamp });
    writeFilePath(allocator, stamp_path_final, stamp_content) catch |err| {
        std.debug.print("[INSTALL] Warning: Failed to write installation stamp: {s}\n", .{@errorName(err)});
    };
    std.debug.print("[INSTALL] Installation stamp written to: {s}\n", .{stamp_path_final});

    // Post-installation cleanup to ensure no processes are left behind
    std.debug.print("[INSTALL] Running post-installation process cleanup\n", .{});
    pid_manager.reapZombies();

    // Final check for any remaining Rosette processes
    std.debug.print("[INSTALL] Final process check\n", .{});
    pid_manager.printTrackedProcessStatus();

    std.debug.print("[INSTALL] Installation/update completed successfully\n", .{});
}

fn uninstallShell(init: std.process.Init, allocator: std.mem.Allocator) !void {
    const home = try homeDir(allocator);
    const rosette_dir = try std.fs.path.join(allocator, &.{ home, ".rosette" });
    const bin_dir = try std.fs.path.join(allocator, &.{ rosette_dir, "bin" });
    const lib_dir = try std.fs.path.join(allocator, &.{ rosette_dir, "lib" });
    const wrapper_dir = try std.fs.path.join(allocator, &.{ rosette_dir, "wrappers" });
    const shell_path = try std.fs.path.join(allocator, &.{ rosette_dir, "rosette-shell.sh" });
    const bash_env_path = try std.fs.path.join(allocator, &.{ rosette_dir, "rosette-bash-env.sh" });
    const helper_path = try std.fs.path.join(allocator, &.{ bin_dir, "rosette-shell" });
    const rosette_path = try std.fs.path.join(allocator, &.{ bin_dir, "rosette" });
    const arch_wrapper_path = try std.fs.path.join(allocator, &.{ bin_dir, "arch" });
    const arch_backend_path = try std.fs.path.join(allocator, &.{ bin_dir, "rosette-arch" });
    const compiler_launcher_path = try std.fs.path.join(allocator, &.{ bin_dir, "rosette-compiler-sanitize" });
    const clean_state_path = try std.fs.path.join(allocator, &.{ bin_dir, "rosette-clean-state" });
    const compat_router_path = try std.fs.path.join(allocator, &.{ bin_dir, "rosette-router" });
    const source_root = try std.fs.path.join(allocator, &.{ rosette_dir, "source-root" });
    const toml_path = try std.fs.path.join(allocator, &.{ rosette_dir, "config.toml" });
    const stamp_path = try std.fs.path.join(allocator, &.{ rosette_dir, ".install-stamp" });
    const elf_processor_path = try std.fs.path.join(allocator, &.{ bin_dir, "elf_processor" });
    const macho_processor_path = try std.fs.path.join(allocator, &.{ bin_dir, "macho_processor" });
    const dyld_lib_path = try std.fs.path.join(allocator, &.{ lib_dir, "rosette-exec.dylib" });

    try removeProfileBlocks(init.io, allocator, home);

    try unlinkIfExists(allocator, shell_path);
    try unlinkIfExists(allocator, bash_env_path);
    try unlinkIfExists(allocator, source_root);
    try unlinkIfExists(allocator, toml_path);
    try unlinkIfExists(allocator, stamp_path);
    try unlinkIfExists(allocator, elf_processor_path);
    try unlinkIfExists(allocator, macho_processor_path);
    try unlinkIfExists(allocator, compat_router_path);
    try unlinkIfExists(allocator, arch_wrapper_path);
    try unlinkIfExists(allocator, arch_backend_path);
    try unlinkIfExists(allocator, compiler_launcher_path);
    try unlinkIfExists(allocator, clean_state_path);
    try unlinkIfExists(allocator, dyld_lib_path);
    try removeWrappers(allocator, wrapper_dir);
    try unlinkIfExists(allocator, helper_path);
    try unlinkIfExists(allocator, rosette_path);
    try unlinkIfExists(allocator, try std.fs.path.join(allocator, &.{ bin_dir, "rosette-c-fix" }));
    rmdirIfEmpty(allocator, wrapper_dir) catch {};
    rmdirIfEmpty(allocator, bin_dir) catch {};
    rmdirIfEmpty(allocator, lib_dir) catch {};
    rmdirIfEmpty(allocator, rosette_dir) catch {};

    std.debug.print("Rosette shell integration removed.\n", .{});
}

fn ensureConfigFile(io: std.Io, allocator: std.mem.Allocator, toml_path: []const u8) !void {
    if (!fileExists(allocator, toml_path)) {
        try writeFilePath(allocator, toml_path, default_config_text);
        try chmodPath(allocator, toml_path, 0o644);
        return;
    }

    const contents = std.Io.Dir.cwd().readFileAlloc(io, toml_path, allocator, .limited(max_text_file)) catch return;
    if (try upgradeConfigText(allocator, contents)) |upgraded| {
        try writeFilePath(allocator, toml_path, upgraded);
        try chmodPath(allocator, toml_path, 0o644);
    }
}

const TomlSectionRange = struct {
    header_end: usize,
    body_end: usize,
};

const CompatConfigLine = struct {
    key: []const u8,
    line: []const u8,
    strict_group: bool = false,
};

const compat_config_lines = [_]CompatConfigLine{
    .{ .key = "allow_rosetta2_fallback", .line = "allow_rosetta2_fallback = true\n" },
    .{ .key = "strict", .line = "strict = false\n", .strict_group = true },
    .{ .key = "abort_on_fallback", .line = "abort_on_fallback = false\n", .strict_group = true },
    .{ .key = "abort_on_unsupported", .line = "abort_on_unsupported = false\n", .strict_group = true },
    .{ .key = "trace", .line = "trace = true\n" },
};

fn upgradeConfigText(allocator: std.mem.Allocator, contents: []const u8) !?[]const u8 {
    const range = findTomlSectionRange(contents, "compat") orelse {
        var out: std.ArrayList(u8) = .empty;
        errdefer out.deinit(allocator);
        try out.appendSlice(allocator, contents);
        if (contents.len != 0 and contents[contents.len - 1] != '\n') try out.append(allocator, '\n');
        if (contents.len != 0) try out.append(allocator, '\n');
        try out.appendSlice(allocator, "[compat]\n");
        try out.appendSlice(allocator, compat_config_upgrade_text);
        return try out.toOwnedSlice(allocator);
    };

    var missing: std.ArrayList(u8) = .empty;
    defer missing.deinit(allocator);
    var wrote_strict_comment = false;
    for (compat_config_lines) |entry| {
        if (compatSettingPresent(contents, range, entry.key)) continue;
        if (entry.strict_group and !wrote_strict_comment) {
            try missing.appendSlice(allocator, "# Strict is for diagnostics: Rosette must own the route, and fallback or\n");
            try missing.appendSlice(allocator, "# unsupported routes abort loudly instead of quietly using Apple Rosetta 2.\n");
            wrote_strict_comment = true;
        }
        try missing.appendSlice(allocator, entry.line);
    }
    if (missing.items.len == 0) return null;

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try out.appendSlice(allocator, contents[0..range.header_end]);
    if (range.header_end != 0 and contents[range.header_end - 1] != '\n') try out.append(allocator, '\n');
    try out.appendSlice(allocator, missing.items);
    try out.appendSlice(allocator, contents[range.header_end..]);
    return try out.toOwnedSlice(allocator);
}

fn findTomlSectionRange(contents: []const u8, wanted: []const u8) ?TomlSectionRange {
    var offset: usize = 0;
    var found = false;
    var header_end: usize = 0;
    while (offset < contents.len) {
        const line_start = offset;
        const newline = std.mem.indexOfScalar(u8, contents[offset..], '\n');
        const line_end = if (newline) |pos| offset + pos else contents.len;
        const next = if (newline) |pos| offset + pos + 1 else contents.len;
        const line = contents[line_start..line_end];
        const no_comment = if (std.mem.indexOfScalar(u8, line, '#')) |pos| line[0..pos] else line;
        const trimmed = std.mem.trim(u8, no_comment, " \t\r\n");
        if (trimmed.len >= 2 and trimmed[0] == '[' and trimmed[trimmed.len - 1] == ']') {
            const name = std.mem.trim(u8, trimmed[1 .. trimmed.len - 1], " \t\r\n");
            if (found) {
                return .{ .header_end = header_end, .body_end = line_start };
            }
            if (std.ascii.eqlIgnoreCase(name, wanted)) {
                found = true;
                header_end = next;
            }
        }
        offset = next;
    }
    if (!found) return null;
    return .{ .header_end = header_end, .body_end = contents.len };
}

fn compatSettingPresent(contents: []const u8, range: TomlSectionRange, key: []const u8) bool {
    if (std.ascii.eqlIgnoreCase(key, "strict")) {
        return tomlRangeHasKey(contents, range, "strict") or tomlRangeHasKey(contents, range, "strict_rosette");
    }
    if (std.ascii.eqlIgnoreCase(key, "abort_on_unsupported")) {
        return tomlRangeHasKey(contents, range, "abort_on_unsupported") or
            tomlRangeHasKey(contents, range, "abort_on_failure") or
            tomlRangeHasKey(contents, range, "trap_on_failure");
    }
    return tomlRangeHasKey(contents, range, key);
}

fn tomlRangeHasKey(contents: []const u8, range: TomlSectionRange, key: []const u8) bool {
    var lines = std.mem.splitScalar(u8, contents[range.header_end..range.body_end], '\n');
    while (lines.next()) |raw_line| {
        const no_comment = if (std.mem.indexOfScalar(u8, raw_line, '#')) |pos| raw_line[0..pos] else raw_line;
        const line = std.mem.trim(u8, no_comment, " \t\r\n");
        if (line.len == 0) continue;
        const eq = std.mem.indexOfScalar(u8, line, '=') orelse continue;
        const parsed_key = std.mem.trim(u8, line[0..eq], " \t\r\n");
        if (std.ascii.eqlIgnoreCase(parsed_key, key)) return true;
    }
    return false;
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

fn routeArch(init: std.process.Init, allocator: std.mem.Allocator, arch_args: []const []const u8) !void {
    const real_arch = "/usr/bin/arch";
    const routed = parseArchRoute(arch_args) orelse {
        try execArgv(init.io, try prependArg(allocator, real_arch, arch_args));
        return;
    };

    const router_path = resolveCompatRouterPath(init, allocator) catch "";
    if (router_path.len == 0 or !canExecute(allocator, router_path)) {
        try execArgv(init.io, try prependArg(allocator, real_arch, arch_args));
        return;
    }
    const trace_path = try compatTracePath(allocator);

    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);
    try argv.append(allocator, router_path);
    try argv.append(allocator, "run");
    try argv.append(allocator, "--prefer-intel");
    try argv.append(allocator, "--trace");
    try argv.append(allocator, trace_path);
    try argv.append(allocator, routed.target);
    for (routed.target_args) |arg| try argv.append(allocator, arg);

    const code = try runArgvResult(init.io, argv.items);
    std.process.exit(code);
}

fn compatTracePath(allocator: std.mem.Allocator) ![]const u8 {
    if (getenvSlice("ROSETTE_COMPAT_TRACE")) |existing| {
        if (existing.len != 0) return try allocator.dupe(u8, existing);
    }

    const base = try compatTraceBase(allocator);
    return try std.fs.path.join(allocator, &.{ base, ".rosette", "rosetta2-handoff.trace.log" });
}

fn compatTraceBase(allocator: std.mem.Allocator) ![]const u8 {
    if (getenvSlice("ROSETTE_TRACE_ROOT")) |root| {
        if (root.len != 0) return try allocator.dupe(u8, root);
    }
    if (getenvSlice("ROSETTE_ROUTE_ROOT")) |root| {
        if (root.len != 0) return try allocator.dupe(u8, root);
    }
    if (getenvSlice("ROSETTE_CALLER_CWD")) |root| {
        if (root.len != 0) return try allocator.dupe(u8, root);
    }
    if (getenvSlice("ROSETTE_PROJECT_ROOT")) |root| {
        if (root.len != 0) return try allocator.dupe(u8, root);
    }
    const cwd = try absolutePath(allocator, ".");
    return try nearestProjectRoot(allocator, cwd);
}

fn nearestProjectRoot(allocator: std.mem.Allocator, start_dir: []const u8) ![]const u8 {
    var current = try allocator.dupe(u8, start_dir);
    while (true) {
        if (hasProjectRootMarker(allocator, current)) return current;
        const parent = std.fs.path.dirname(current) orelse break;
        if (std.mem.eql(u8, parent, current)) break;
        current = try allocator.dupe(u8, parent);
    }
    return try allocator.dupe(u8, start_dir);
}

fn hasProjectRootMarker(allocator: std.mem.Allocator, dir: []const u8) bool {
    const markers = [_][]const u8{ ".git", ".rosette-project", "build.zig", "CMakeLists.txt", "Makefile", "GNUmakefile", "package.json", "pyproject.toml", "Cargo.toml", "xb" };
    for (markers) |marker| {
        const candidate = std.fs.path.join(allocator, &.{ dir, marker }) catch continue;
        if (fileExists(allocator, candidate)) return true;
    }
    return false;
}

const ArchRoute = struct {
    target: []const u8,
    target_args: []const []const u8,
};

fn parseArchRoute(args: []const []const u8) ?ArchRoute {
    if (args.len < 2) return null;
    if (std.mem.eql(u8, args[0], "-x86_64")) {
        return .{ .target = args[1], .target_args = args[2..] };
    }
    if (args.len >= 3 and std.mem.eql(u8, args[0], "-arch") and std.mem.eql(u8, args[1], "x86_64")) {
        return .{ .target = args[2], .target_args = args[3..] };
    }
    return null;
}

fn prependArg(allocator: std.mem.Allocator, first: []const u8, rest: []const []const u8) ![]const []const u8 {
    var argv = try allocator.alloc([]const u8, rest.len + 1);
    argv[0] = first;
    for (rest, 0..) |arg, i| argv[i + 1] = arg;
    return argv;
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

const CleanOptions = struct {
    dry_run: bool = false,
    include_xenia: bool = true,
};

const ProcessInfo = struct {
    pid: i32,
    ppid: i32,
    stat: []const u8,
    command: []const u8,
};

const CleanupCandidate = struct {
    process: ProcessInfo,
    reason: []const u8,
};

fn cleanState(init: std.process.Init, allocator: std.mem.Allocator, args: []const []const u8) !void {
    const backend = resolveCleanStateBackend(init, allocator) catch |err| {
        std.debug.print(
            "rosette-shell: clean-state backend is not installed ({s}); run `make shell-update`.\n",
            .{@errorName(err)},
        );
        std.process.exit(127);
    };
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);
    try argv.append(allocator, backend);
    for (args) |arg| try argv.append(allocator, arg);
    execArgvReplace(allocator, argv.items) catch |err| {
        std.debug.print("rosette-shell: failed to exec clean-state backend: {s}\n", .{@errorName(err)});
        std.process.exit(127);
    };
}

fn resolveCleanStateBackend(init: std.process.Init, allocator: std.mem.Allocator) ![]const u8 {
    if (getenvSlice("ROSETTE_CLEAN_STATE")) |path| {
        if (canExecute(allocator, path)) return try allocator.dupe(u8, path);
    }

    const helper_path = currentHelperPath(init, allocator) catch "";
    if (helper_path.len != 0) {
        if (std.fs.path.dirname(helper_path)) |helper_dir| {
            const sibling = try std.fs.path.join(allocator, &.{ helper_dir, "rosette-clean-state" });
            if (canExecute(allocator, sibling)) return sibling;
        }
    }

    if (getenvSlice("HOME")) |home| {
        const installed = try std.fs.path.join(allocator, &.{ home, ".rosette", "bin", "rosette-clean-state" });
        if (canExecute(allocator, installed)) return installed;
    }

    return error.CleanStateBackendMissing;
}

fn parseCleanOptions(args: []const []const u8) !CleanOptions {
    var options = CleanOptions{};
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--dry-run") or std.mem.eql(u8, arg, "--scan")) {
            options.dry_run = true;
        } else if (std.mem.eql(u8, arg, "--no-xenia")) {
            options.include_xenia = false;
        } else if (std.mem.eql(u8, arg, "--xenia")) {
            options.include_xenia = true;
        } else {
            std.debug.print("rosette-shell: unknown clean-state option: {s}\n", .{arg});
            return error.InvalidCleanStateOption;
        }
    }
    return options;
}

fn collectCleanupCandidates(allocator: std.mem.Allocator, options: CleanOptions) ![]CleanupCandidate {
    const processes = try readProcessSnapshot(allocator);
    var candidates: std.ArrayList(CleanupCandidate) = .empty;
    errdefer candidates.deinit(allocator);

    const self_pid: i32 = @intCast(c.getpid());
    const parent_pid: i32 = @intCast(c.getppid());
    for (processes) |process| {
        if (process.pid <= 1) continue;
        if (process.pid == self_pid or process.pid == parent_pid) continue;
        if (process.ppid == self_pid) continue;
        if (cleanupReason(process.command, options)) |reason| {
            try candidates.append(allocator, .{
                .process = process,
                .reason = reason,
            });
        }
    }
    return try candidates.toOwnedSlice(allocator);
}

fn cleanupReason(command: []const u8, options: CleanOptions) ?[]const u8 {
    if (containsIgnoreCase(command, " rosette-shell clean-state")) return null;
    if (containsIgnoreCase(command, "/rosette-shell clean-state")) return null;
    if (!options.include_xenia and containsIgnoreCase(command, "xenia_canary.app/contents/macos/xenia_canary")) return null;
    if (containsIgnoreCase(command, "rosette-shell compiler-sanitize")) return "Rosette compiler sanitizer";
    if (containsIgnoreCase(command, "rosette-compiler-sanitize")) return "Rosette compiler sanitizer launcher";
    if (containsIgnoreCase(command, "rosette-shell route-arch")) return "Rosette arch handoff";
    if (containsIgnoreCase(command, "rosette-arch")) return "Rosette arch backend";
    if (containsIgnoreCase(command, "rosette-shell detect")) return "Rosette project detector";
    if (containsIgnoreCase(command, "rosette-shell recipe-shell")) return "Rosette make recipe shell";
    if (containsIgnoreCase(command, "rosette-shell tool")) return "Rosette compiler/tool wrapper";
    if (containsIgnoreCase(command, "rosette-router")) return "Rosette compatibility router";
    if (containsIgnoreCase(command, "elf_processor")) return "Rosette ELF processor";
    if (containsIgnoreCase(command, "rosette_assembler_runner")) return "Rosette assembler ABI runner";
    if (containsIgnoreCase(command, "rosette_exe_runner")) return "Rosette EXE runner";
    if (containsIgnoreCase(command, "rosette_mscoree_window_helper")) return "Rosette managed window helper";
    if (containsIgnoreCase(command, "/usr/local/bin/rose")) return "legacy Rosette launcher";
    if (containsIgnoreCase(command, "xenia-rosetta.")) return "Rosette Xenia handoff script";
    if (options.include_xenia and containsIgnoreCase(command, "xenia_canary.app/contents/macos/xenia_canary")) return "Rosette-launched Xenia Canary";
    return null;
}

fn readProcessSnapshot(allocator: std.mem.Allocator) ![]ProcessInfo {
    if (comptime builtin.target.os.tag == .macos) {
        return try readDarwinProcessSnapshot(allocator);
    }
    return error.ProcessSnapshotUnsupported;
}

fn readDarwinProcessSnapshot(allocator: std.mem.Allocator) ![]ProcessInfo {
    var pid_capacity: usize = 4096;
    while (pid_capacity <= 65536) : (pid_capacity *= 2) {
        const pids = try allocator.alloc(c_int, pid_capacity);
        const bytes = c.proc_listallpids(pids.ptr, @as(c_int, @intCast(pids.len * @sizeOf(c_int))));
        if (bytes < 0) return error.ProcessSnapshotFailed;
        const count: usize = @intCast(@divTrunc(bytes, @as(c_int, @intCast(@sizeOf(c_int)))));
        if (count < pids.len) {
            return try buildDarwinProcessSnapshot(allocator, pids[0..count]);
        }
    }
    return error.ProcessSnapshotTooLarge;
}

fn buildDarwinProcessSnapshot(allocator: std.mem.Allocator, pids: []const c_int) ![]ProcessInfo {
    var processes: std.ArrayList(ProcessInfo) = .empty;
    errdefer processes.deinit(allocator);
    for (pids) |pid| {
        if (pid <= 0) continue;
        if (readDarwinProcessInfo(allocator, pid)) |process| {
            try processes.append(allocator, process);
        } else |_| {}
    }
    return try processes.toOwnedSlice(allocator);
}

fn readDarwinProcessInfo(allocator: std.mem.Allocator, pid: c_int) !ProcessInfo {
    var path_buffer: [c.PROC_PIDPATHINFO_MAXSIZE]u8 = undefined;
    @memset(&path_buffer, 0);
    const path_len = c.proc_pidpath(pid, &path_buffer, path_buffer.len);
    const path = if (path_len > 0)
        std.mem.sliceTo(path_buffer[0..@as(usize, @intCast(path_len))], 0)
    else
        "";

    const command = try readDarwinProcessCommand(allocator, pid, path);
    if (command.len == 0) return error.InvalidProcessLine;

    return .{
        .pid = @intCast(pid),
        .ppid = try readDarwinParentPid(pid),
        .stat = try allocator.dupe(u8, "unknown"),
        .command = command,
    };
}

fn readDarwinProcessCommand(allocator: std.mem.Allocator, pid: c_int, path: []const u8) ![]const u8 {
    var mib = [_]c_int{ c.CTL_KERN, c.KERN_PROCARGS2, pid };
    var buffer = try allocator.alloc(u8, 128 * 1024);
    var size: usize = buffer.len;
    if (c.sysctl(&mib, mib.len, buffer.ptr, &size, null, 0) != 0) {
        if (path.len != 0) return try allocator.dupe(u8, path);
        return error.InvalidProcessLine;
    }

    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    if (path.len != 0) try out.appendSlice(allocator, path);

    const bytes = buffer[0..size];
    var index: usize = @sizeOf(c_int);
    var strings_seen: usize = 0;
    while (index < bytes.len and strings_seen < 64 and out.items.len < 64 * 1024) {
        while (index < bytes.len and bytes[index] == 0) : (index += 1) {}
        const start = index;
        while (index < bytes.len and bytes[index] != 0) : (index += 1) {}
        if (index <= start) continue;
        const value = bytes[start..index];
        strings_seen += 1;
        if (value.len == 0) continue;
        if (path.len != 0 and std.mem.eql(u8, value, path)) continue;
        if (out.items.len != 0) try out.append(allocator, ' ');
        try out.appendSlice(allocator, value);
    }

    return out.items;
}

fn readDarwinParentPid(pid: c_int) !i32 {
    var mib = [_]c_int{ c.CTL_KERN, c.KERN_PROC, c.KERN_PROC_PID, pid };
    var info: c.struct_kinfo_proc = undefined;
    var size: usize = @sizeOf(c.struct_kinfo_proc);
    if (c.sysctl(&mib, mib.len, &info, &size, null, 0) != 0 or size < @sizeOf(c.struct_kinfo_proc)) {
        return 0;
    }
    return @intCast(info.kp_eproc.e_ppid);
}

fn parseProcessLine(allocator: std.mem.Allocator, raw_line: []const u8) !ProcessInfo {
    var line = std.mem.trim(u8, raw_line, " \t\r\n");
    if (line.len == 0) return error.InvalidProcessLine;
    const pid_text = takeField(&line) orelse return error.InvalidProcessLine;
    const ppid_text = takeField(&line) orelse return error.InvalidProcessLine;
    const stat_text = takeField(&line) orelse return error.InvalidProcessLine;
    const command = std.mem.trim(u8, line, " \t\r\n");
    if (command.len == 0) return error.InvalidProcessLine;
    return .{
        .pid = try std.fmt.parseInt(i32, pid_text, 10),
        .ppid = try std.fmt.parseInt(i32, ppid_text, 10),
        .stat = try allocator.dupe(u8, stat_text),
        .command = try allocator.dupe(u8, command),
    };
}

fn takeField(line: *[]const u8) ?[]const u8 {
    line.* = trimLeftSpaces(line.*);
    if (line.*.len == 0) return null;
    var end: usize = 0;
    while (end < line.*.len and line.*[end] != ' ' and line.*[end] != '\t') : (end += 1) {}
    const field = line.*[0..end];
    line.* = line.*[end..];
    return field;
}

fn trimLeftSpaces(line: []const u8) []const u8 {
    var start: usize = 0;
    while (start < line.len and (line[start] == ' ' or line[start] == '\t')) : (start += 1) {}
    return line[start..];
}

fn signalCleanupCandidate(candidate: CleanupCandidate, sig: c_int) void {
    const rc = c.kill(candidate.process.pid, sig);
    if (rc == 0) {
        std.debug.print(
            "rosette-shell: sent {s} to pid={d} reason={s}\n",
            .{ signalName(sig), candidate.process.pid, candidate.reason },
        );
    } else {
        const err_name = errnoName(currentErrno());
        std.debug.print(
            "rosette-shell: failed {s} pid={d} reason={s}: {s}\n",
            .{ signalName(sig), candidate.process.pid, candidate.reason, err_name },
        );
    }
}

fn printCleanupCandidate(prefix: []const u8, candidate: CleanupCandidate) void {
    std.debug.print(
        "{s}: pid={d} ppid={d} stat={s} reason={s}\n  command: {s}\n",
        .{
            prefix,
            candidate.process.pid,
            candidate.process.ppid,
            candidate.process.stat,
            candidate.reason,
            candidate.process.command,
        },
    );
}

fn samePidInCandidates(pid: i32, candidates: []const CleanupCandidate) bool {
    for (candidates) |candidate| {
        if (candidate.process.pid == pid) return true;
    }
    return false;
}

fn isKernelHeldStatus(stat: []const u8) bool {
    return std.mem.indexOfScalar(u8, stat, 'U') != null or
        std.mem.indexOfScalar(u8, stat, 'E') != null;
}

fn signalName(sig: c_int) []const u8 {
    if (sig == c.SIGTERM) return "SIGTERM";
    if (sig == c.SIGKILL) return "SIGKILL";
    return "signal";
}

fn errnoName(err: c_int) []const u8 {
    return switch (err) {
        c.ESRCH => "process not found",
        c.EPERM => "permission denied",
        c.EINVAL => "invalid signal",
        else => "unknown errno",
    };
}

fn currentErrno() c_int {
    if (@hasDecl(c, "__error")) return c.__error().*;
    if (@hasDecl(c, "__errno_location")) return c.__errno_location().*;
    return 0;
}

fn sleepMillis(ms: u32) void {
    _ = c.usleep(@as(c_uint, ms) * 1000);
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
        \\: "${ROSETTE_ROUTER:=$HOME/.rosette/bin/rosette-router}"
        \\export ROSETTE_ROUTER
        \\: "${ROSETTE_COMPILER_SANITIZER:=$HOME/.rosette/bin/rosette-compiler-sanitize}"
        \\export ROSETTE_COMPILER_SANITIZER
        \\: "${ROSETTE_X86_INTRINSICS_COMPAT:=$HOME/.rosette/include/x86_intrinsics_compat.h}"
        \\export ROSETTE_X86_INTRINSICS_COMPAT
        \\if [ -z "${ROSETTE_SHELL_DISABLE:-}" ] && [ "${ROSETTE_COMPILER_SANITIZER_ENABLE:-auto}" != "0" ] && [ -x "$ROSETTE_COMPILER_SANITIZER" ]; then
        \\  : "${CMAKE_C_COMPILER_LAUNCHER:=$ROSETTE_COMPILER_SANITIZER}"
        \\  : "${CMAKE_CXX_COMPILER_LAUNCHER:=$ROSETTE_COMPILER_SANITIZER}"
        \\  export CMAKE_C_COMPILER_LAUNCHER CMAKE_CXX_COMPILER_LAUNCHER
        \\fi
        \\export ROSETTE_BASH_ENV="$HOME/.rosette/rosette-bash-env.sh"
        \\if [ -f "$ROSETTE_BASH_ENV" ]; then
        \\  if [ "${BASH_ENV:-}" != "$ROSETTE_BASH_ENV" ]; then
        \\    export ROSETTE_USER_BASH_ENV="${BASH_ENV:-}"
        \\    export BASH_ENV="$ROSETTE_BASH_ENV"
        \\  fi
        \\fi
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
        \\__rosette_should_probe_direct_elf() {
        \\  emulate -L zsh
        \\  local __rosette_makefile
        \\  local -a __rosette_asm_files
        \\  if [ -f Makefile ]; then
        \\    __rosette_makefile=Makefile
        \\  elif [ -f makefile ]; then
        \\    __rosette_makefile=makefile
        \\  else
        \\    return 1
        \\  fi
        \\  __rosette_asm_files=( ./*.asm(N[1,1]) )
        \\  if (( ${#__rosette_asm_files[@]} == 0 )); then
        \\    return 1
        \\  fi
        \\  command grep -Eiq "yasm" "$__rosette_makefile" 2>/dev/null || return 1
        \\  command grep -Eiq "elf64" "$__rosette_makefile" 2>/dev/null || return 1
        \\  return 0
        \\}
        \\__rosette_detect_project_with_timeout() {
        \\  emulate -L zsh
        \\  local __rosette_detect_timeout="${ROSETTE_DIRECT_ELF_DETECT_TIMEOUT_MS:-500}"
        \\  local __rosette_done="${TMPDIR:-/tmp}/rosette-detect.$$.$RANDOM"
        \\  local __rosette_pid __rosette_elapsed=0 __rosette_status=1
        \\  ( "$ROSETTE_SHELL_HELPER" detect "$PWD" >/dev/null 2>&1; print -r -- "$?" > "$__rosette_done" ) &
        \\  __rosette_pid=$!
        \\  while kill -0 "$__rosette_pid" 2>/dev/null; do
        \\    if (( __rosette_elapsed >= __rosette_detect_timeout )); then
        \\      kill -TERM "$__rosette_pid" 2>/dev/null || true
        \\      sleep 0.05
        \\      kill -KILL "$__rosette_pid" 2>/dev/null || true
        \\      rm -f "$__rosette_done"
        \\      return 1
        \\    fi
        \\    sleep 0.05
        \\    __rosette_elapsed=$((__rosette_elapsed + 50))
        \\  done
        \\  wait "$__rosette_pid" 2>/dev/null || true
        \\  if [ -f "$__rosette_done" ]; then
        \\    IFS= read -r __rosette_status < "$__rosette_done" 2>/dev/null || __rosette_status=1
        \\    rm -f "$__rosette_done"
        \\    return "$__rosette_status"
        \\  fi
        \\  return 1
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
        \\  if ! __rosette_should_probe_direct_elf; then
        \\    [ "${ROSETTE_SHELL_DEBUG:-0}" = "1" ] && print -r -- "rosette-shell: direct ELF launch skipped by cheap prefilter in $PWD" >&2
        \\    return 0
        \\  fi
        \\  if [ "${ROSETTE_DIRECT_ELF_FULL_DETECT:-0}" = "1" ]; then
        \\    if ! __rosette_detect_project_with_timeout; then
        \\      [ "${ROSETTE_SHELL_DEBUG:-0}" = "1" ] && print -r -- "rosette-shell: direct ELF launch disabled; project detector timed out or did not match $PWD" >&2
        \\      return 0
        \\    fi
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
        \\      local __rosette_make_arg
        \\      for __rosette_make_arg in "$@"; do
        \\        case "$__rosette_make_arg" in
        \\          shell|shell-update|install-shell|shell-uninstall|shell-clean-state|app-wrapper|installer|uninstaller|app-all|notarize-installer|notarize-uninstaller|notarize-app-all)
        \\            ROSETTE_SHELL_DISABLE=1 command make "$@"
        \\            __rosette_status=$?
        \\            __rosette_after_make "$__rosette_status" "$@"
        \\            return "$?"
        \\            ;;
        \\        esac
        \\      done
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

fn buildBashEnvSnippet(allocator: std.mem.Allocator, helper_path: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    try out.appendSlice(allocator,
        \\# Rosette non-interactive bash hook.
        \\# Sourced through BASH_ENV so scripts that invoke `arch -x86_64 ...`
        \\# can be traced and routed without editing those scripts.
        \\
        \\if [ -n "${ROSETTE_USER_BASH_ENV:-}" ] && [ "$ROSETTE_USER_BASH_ENV" != "${ROSETTE_BASH_ENV:-}" ] && [ -f "$ROSETTE_USER_BASH_ENV" ]; then
        \\  . "$ROSETTE_USER_BASH_ENV"
        \\fi
        \\
        \\export ROSETTE_SHELL_HELPER=
    );
    try appendShellQuoted(&out, allocator, helper_path);
    try out.appendSlice(allocator,
        \\
        \\: "${ROSETTE_COMPILER_SANITIZER:=$HOME/.rosette/bin/rosette-compiler-sanitize}"
        \\export ROSETTE_COMPILER_SANITIZER
        \\: "${ROSETTE_X86_INTRINSICS_COMPAT:=$HOME/.rosette/include/x86_intrinsics_compat.h}"
        \\export ROSETTE_X86_INTRINSICS_COMPAT
        \\if [ -z "${ROSETTE_SHELL_DISABLE:-}" ] && [ "${ROSETTE_COMPILER_SANITIZER_ENABLE:-auto}" != "0" ] && [ -x "$ROSETTE_COMPILER_SANITIZER" ]; then
        \\  : "${CMAKE_C_COMPILER_LAUNCHER:=$ROSETTE_COMPILER_SANITIZER}"
        \\  : "${CMAKE_CXX_COMPILER_LAUNCHER:=$ROSETTE_COMPILER_SANITIZER}"
        \\  export CMAKE_C_COMPILER_LAUNCHER CMAKE_CXX_COMPILER_LAUNCHER
        \\fi
        \\
        \\__rosette_env_path_prepend() {
        \\  local __rosette_var="$1"
        \\  local __rosette_entry="$2"
        \\  local __rosette_old="${!__rosette_var:-}"
        \\  [ -n "$__rosette_entry" ] && [ -d "$__rosette_entry" ] || return 1
        \\  case ":$__rosette_old:" in
        \\    *":$__rosette_entry:"*) return 1 ;;
        \\  esac
        \\  if [ -n "$__rosette_old" ]; then
        \\    export "$__rosette_var=$__rosette_entry:$__rosette_old"
        \\  else
        \\    export "$__rosette_var=$__rosette_entry"
        \\  fi
        \\  return 0
        \\}
        \\
        \\__rosette_dir_has_direct_headers() {
        \\  local __rosette_dir="$1"
        \\  local __rosette_match
        \\  [ -d "$__rosette_dir" ] || return 1
        \\  for __rosette_match in "$__rosette_dir"/*.h "$__rosette_dir"/*.hh "$__rosette_dir"/*.hpp "$__rosette_dir"/*.hxx; do
        \\    [ -e "$__rosette_match" ] && return 0
        \\  done
        \\  return 1
        \\}
        \\
        \\__rosette_dir_has_child_headers() {
        \\  local __rosette_dir="$1"
        \\  local __rosette_child
        \\  [ -d "$__rosette_dir" ] || return 1
        \\  for __rosette_child in "$__rosette_dir"/*; do
        \\    [ -d "$__rosette_child" ] || continue
        \\    __rosette_dir_has_direct_headers "$__rosette_child" && return 0
        \\  done
        \\  return 1
        \\}
        \\
        \\__rosette_dir_has_standard_header_shadow() {
        \\  local __rosette_dir="$1"
        \\  local __rosette_name
        \\  [ -d "$__rosette_dir" ] || return 1
        \\  for __rosette_name in algorithm any array atomic barrier bit bitset charconv chrono codecvt compare complex concepts condition_variable coroutine cstddef cstdint cstdio cstdlib cstring deque exception execution filesystem format forward_list fstream functional future initializer_list iomanip ios iosfwd iostream istream iterator latch limits list locale map memory memory_resource mutex new numbers numeric optional ostream queue random ranges ratio regex scoped_allocator semaphore set shared_mutex source_location span sstream stack stdexcept stop_token streambuf string string_view strstream syncstream system_error thread tuple type_traits typeindex typeinfo unordered_map unordered_set utility valarray variant vector version; do
        \\    [ -e "$__rosette_dir/$__rosette_name" ] && return 0
        \\  done
        \\  return 1
        \\}
        \\
        \\__rosette_dir_has_x86_intrinsic_shadow() {
        \\  local __rosette_dir="$1"
        \\  local __rosette_name
        \\  [ -d "$__rosette_dir" ] || return 1
        \\  for __rosette_name in adxintrin.h ammintrin.h avx2intrin.h avx512bfintrin.h avx512bitalgintrin.h avx512bwbf16vlintrin.h avx512bwintrin.h avx512cdintrin.h avx512dqintrin.h avx512erintrin.h avx512fintrin.h avx512fp16intrin.h avx512ifmainintrin.h avx512ifmavlintrin.h avx512pfintrin.h avx512vbmi2intrin.h avx512vbmiintrin.h avx512vlbitalgintrin.h avx512vlbwintrin.h avx512vldqintrin.h avx512vlintrin.h avx512vlvbmi2intrin.h avx512vlvnniintrin.h avx512vnniintrin.h avx512vp2intersectintrin.h avx512vpopcntdqintrin.h avx512vpopcntdqvlintrin.h avx512vpopcntintrin.h avx512vpopcntvlintrin.h avx512vpshufbitqmbintrin.h avxintrin.h avxintrin512.h bmi2intrin.h bmiintrin.h clflushoptintrin.h clwbintrin.h cpuid.h emmintrin.h f16cintrin.h fma4intrin.h fmaintrin.h fxsrintrin.h ia32intrin.h immintrin.h lwpintrin.h lzcntintrin.h mmintrin.h movdirintrin.h mwaitxintrin.h nmmintrin.h pconfigintrin.h pkuintrin.h pmmintrin.h popcntintrin.h prfchwintrin.h rdseedintrin.h rtmintrin.h serializeintrin.h sgxintrin.h shaintrin.h smmintrin.h tbmintrin.h tmmintrin.h uintrintrin.h vaesintrin.h vpclmulqdqintrin.h waitpkgintrin.h wbnoinvdintrin.h wmmintrin.h x86gprintrin.h x86intrin.h xmmintrin.h xopintrin.h; do
        \\    [ -e "$__rosette_dir/$__rosette_name" ] && return 0
        \\  done
        \\  return 1
        \\}
        \\
        \\__rosette_dir_is_safe_include_root() {
        \\  local __rosette_dir="$1"
        \\  [ -d "$__rosette_dir" ] || return 1
        \\  __rosette_dir_has_x86_intrinsic_shadow "$__rosette_dir" && return 1
        \\  __rosette_dir_has_standard_header_shadow "$__rosette_dir" && return 1
        \\  __rosette_dir_has_direct_headers "$__rosette_dir" && return 0
        \\  __rosette_dir_has_child_headers "$__rosette_dir" && return 0
        \\  return 1
        \\}
        \\
        \\__rosette_trace_project_includes() {
        \\  [ -n "${ROSETTE_COMPAT_TRACE:-}" ] || return 0
        \\  {
        \\    printf '# Rosette project include compatibility\n'
        \\    printf 'event = "project_include_compat"\n'
        \\    printf 'root = "%s"\n' "$1"
        \\    printf 'include_dirs = "%s"\n' "$2"
        \\    printf '\n'
        \\  } >> "$ROSETTE_COMPAT_TRACE" 2>/dev/null || true
        \\}
        \\
        \\__rosette_add_project_include_dir() {
        \\  local __rosette_dir="$1"
        \\  __rosette_dir_is_safe_include_root "$__rosette_dir" || return 1
        \\  if __rosette_env_path_prepend CPATH "$__rosette_dir"; then
        \\    __rosette_added="${__rosette_added:+$__rosette_added:}$__rosette_dir"
        \\    return 0
        \\  fi
        \\  return 1
        \\}
        \\
        \\__rosette_apply_project_include_compat() {
        \\  case "${ROSETTE_PROJECT_INCLUDE_COMPAT:-${ROSETTE_THIRD_PARTY_INCLUDE_COMPAT:-auto}}" in
        \\    0|off|OFF|false|FALSE|no|NO) return 0 ;;
        \\  esac
        \\
        \\  local __rosette_root __rosette_vendor __rosette_pkg __rosette_candidate __rosette_added
        \\  for __rosette_root in "${ROSETTE_PROJECT_INCLUDE_ROOT:-}" "${ROSETTE_THIRD_PARTY_INCLUDE_ROOT:-}" "${ROSETTE_ROUTE_ROOT:-}" "${ROSETTE_CALLER_CWD:-}" "${ROSETTE_PROJECT_ROOT:-}" "$PWD"; do
        \\    [ -n "$__rosette_root" ] && [ -d "$__rosette_root" ] || continue
        \\    __rosette_added=""
        \\
        \\    for __rosette_candidate in "$__rosette_root" "$__rosette_root/include" "$__rosette_root/inc" "$__rosette_root/src" "$__rosette_root/lib"; do
        \\      __rosette_add_project_include_dir "$__rosette_candidate" || true
        \\    done
        \\
        \\    for __rosette_vendor in "$__rosette_root/third_party" "$__rosette_root/vendor" "$__rosette_root/external" "$__rosette_root/extern" "$__rosette_root/deps" "$__rosette_root/dependencies" "$__rosette_root/libraries"; do
        \\      [ -d "$__rosette_vendor" ] || continue
        \\      for __rosette_pkg in "$__rosette_vendor"/*; do
        \\        [ -d "$__rosette_pkg" ] || continue
        \\        for __rosette_candidate in "$__rosette_pkg" "$__rosette_pkg/include" "$__rosette_pkg/inc" "$__rosette_pkg/src" "$__rosette_pkg/lib"; do
        \\          __rosette_add_project_include_dir "$__rosette_candidate" || true
        \\        done
        \\      done
        \\    done
        \\
        \\    if [ -n "$__rosette_added" ]; then
        \\      export ROSETTE_PROJECT_INCLUDE_DIRS="${__rosette_added}${ROSETTE_PROJECT_INCLUDE_DIRS:+:$ROSETTE_PROJECT_INCLUDE_DIRS}"
        \\      __rosette_trace_project_includes "$__rosette_root" "$__rosette_added"
        \\    fi
        \\    return 0
        \\  done
        \\}
        \\
        \\__rosette_apply_project_include_compat
        \\
        \\arch() {
        \\  local __rosette_arch_backend="${ROSETTE_ARCH_BACKEND:-$HOME/.rosette/bin/rosette-arch}"
        \\  if [ -n "${ROSETTE_SHELL_DISABLE:-}" ]; then
        \\    command /usr/bin/arch "$@"
        \\    return $?
        \\  fi
        \\  case "${1:-}" in
        \\    -x86_64)
        \\      if [ "$#" -ge 2 ] && [ -x "$__rosette_arch_backend" ]; then
        \\        ROSETTE_CALLER_CWD="${ROSETTE_CALLER_CWD:-$PWD}" "$__rosette_arch_backend" "$@"
        \\        return $?
        \\      fi
        \\      ;;
        \\    -arch)
        \\      if [ "${2:-}" = "x86_64" ] && [ "$#" -ge 3 ] && [ -x "$__rosette_arch_backend" ]; then
        \\        ROSETTE_CALLER_CWD="${ROSETTE_CALLER_CWD:-$PWD}" "$__rosette_arch_backend" "$@"
        \\        return $?
        \\      fi
        \\      ;;
        \\  esac
        \\  command /usr/bin/arch "$@"
        \\}
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

fn ensureArchWrapper(allocator: std.mem.Allocator, arch_wrapper_path: []const u8, arch_backend_path: []const u8) !void {
    const script = try buildArchWrapperScript(allocator, arch_backend_path);
    try writeFilePath(allocator, arch_wrapper_path, script);
    try chmodPath(allocator, arch_wrapper_path, 0o755);
}

fn buildArchWrapperScript(allocator: std.mem.Allocator, arch_backend_path: []const u8) ![]const u8 {
    return try std.fmt.allocPrint(allocator,
        \\#!/bin/sh
        \\# Generated by Rosette. Route x86_64 arch handoffs before Apple Rosetta 2.
        \\ROSETTE_ARCH_BACKEND=${{ROSETTE_ARCH_BACKEND:-{s}}}
        \\if [ -z "${{ROSETTE_SCRIPT_HANDOFF_ACTIVE:-}}" ] && [ -z "${{ROSETTE_SHELL_DISABLE:-}}" ] && [ -x "$ROSETTE_ARCH_BACKEND" ]; then
        \\  case "${{1:-}}" in
        \\    -x86_64)
        \\      ROSETTE_CALLER_CWD="${{ROSETTE_CALLER_CWD:-$PWD}}" exec "$ROSETTE_ARCH_BACKEND" "$@"
        \\      ;;
        \\    -arch)
        \\      if [ "${{2:-}}" = "x86_64" ]; then
        \\        ROSETTE_CALLER_CWD="${{ROSETTE_CALLER_CWD:-$PWD}}" exec "$ROSETTE_ARCH_BACKEND" "$@"
        \\      fi
        \\      ;;
        \\  esac
        \\fi
        \\exec /usr/bin/arch "$@"
        \\
    , .{try shellSingleQuoted(allocator, arch_backend_path)});
}

fn ensureArchBackend(allocator: std.mem.Allocator, arch_backend_path: []const u8) !void {
    try writeFilePath(allocator, arch_backend_path, arch_backend_script);
    try chmodPath(allocator, arch_backend_path, 0o755);
}

fn ensureCompilerLauncher(allocator: std.mem.Allocator, compiler_launcher_path: []const u8, helper_path: []const u8) !void {
    _ = helper_path;
    try writeFilePath(allocator, compiler_launcher_path, compiler_launcher_script);
    try chmodPath(allocator, compiler_launcher_path, 0o755);
}

const compiler_launcher_script =
    \\#!/bin/bash
    \\# Generated by Rosette. Sanitize compiler command lines without editing projects.
    \\set +e
    \\unset DYLD_INSERT_LIBRARIES
    \\
    \\if [ "$#" -eq 0 ]; then
    \\  echo "rosette-compiler-sanitize: missing compiler argv" >&2
    \\  exit 64
    \\fi
    \\
    \\compiler="$1"
    \\shift
    \\x86_compat_header="${ROSETTE_X86_INTRINSICS_COMPAT:-$HOME/.rosette/include/x86_intrinsics_compat.h}"
    \\macos_shim_root="${ROSETTE_MACOS_COMPAT_INCLUDE_ROOT:-$HOME/.rosette/include}"
    \\
    \\__rosette_compiler_arg_is_x86() {
    \\  case "$1" in
    \\    x86_64|x86_64-*|*-x86_64-*|amd64|amd64-*|*-amd64-*) return 0 ;;
    \\  esac
    \\  return 1
    \\}
    \\
    \\__rosette_path_has_x86_intrinsic_shadow() {
    \\  local dir="$1"
    \\  local name
    \\  [ -d "$dir" ] || return 1
    \\  for name in adxintrin.h ammintrin.h avx2intrin.h avx512bfintrin.h avx512bitalgintrin.h avx512bwbf16vlintrin.h avx512bwintrin.h avx512cdintrin.h avx512dqintrin.h avx512erintrin.h avx512fintrin.h avx512fp16intrin.h avx512ifmainintrin.h avx512ifmavlintrin.h avx512pfintrin.h avx512vbmi2intrin.h avx512vbmiintrin.h avx512vlbitalgintrin.h avx512vlbwintrin.h avx512vldqintrin.h avx512vlintrin.h avx512vlvbmi2intrin.h avx512vlvnniintrin.h avx512vnniintrin.h avx512vp2intersectintrin.h avx512vpopcntdqintrin.h avx512vpopcntdqvlintrin.h avx512vpopcntintrin.h avx512vpopcntvlintrin.h avx512vpshufbitqmbintrin.h avxintrin.h avxintrin512.h bmi2intrin.h bmiintrin.h clflushoptintrin.h clwbintrin.h cpuid.h emmintrin.h f16cintrin.h fma4intrin.h fmaintrin.h fxsrintrin.h ia32intrin.h immintrin.h lwpintrin.h lzcntintrin.h mmintrin.h movdirintrin.h mwaitxintrin.h nmmintrin.h pconfigintrin.h pkuintrin.h pmmintrin.h popcntintrin.h prfchwintrin.h rdseedintrin.h rtmintrin.h serializeintrin.h sgxintrin.h shaintrin.h smmintrin.h tbmintrin.h tmmintrin.h uintrintrin.h vaesintrin.h vpclmulqdqintrin.h waitpkgintrin.h wbnoinvdintrin.h wmmintrin.h x86gprintrin.h x86intrin.h xmmintrin.h xopintrin.h; do
    \\    [ -e "$dir/$name" ] && return 0
    \\  done
    \\  return 1
    \\}
    \\
    \\target_x86=0
    \\prev=""
    \\for arg in "$@"; do
    \\  if [ -n "$prev" ]; then
    \\    if __rosette_compiler_arg_is_x86 "$arg"; then
    \\      target_x86=1
    \\    fi
    \\    prev=""
    \\    continue
    \\  fi
    \\  case "$arg" in
    \\    -arch|-target|--target)
    \\      prev="$arg"
    \\      ;;
    \\    -arch=*|-target=*|--target=*)
    \\      value="${arg#*=}"
    \\      if __rosette_compiler_arg_is_x86 "$value"; then
    \\        target_x86=1
    \\      fi
    \\      ;;
    \\  esac
    \\done
    \\
    \\filtered=()
    \\__rosette_add_macos_compat_header() {
    \\  local header="$1"
    \\  [ -f "$header" ] || return 0
    \\  filtered+=("-include" "$header")
    \\}
    \\__rosette_add_macos_warning_compat_flags() {
    \\  [ "$(uname -s 2>/dev/null)" = "Darwin" ] || return 0
    \\  [ "${ROSETTE_MACOS_WARNING_COMPAT_ENABLE:-auto}" != "0" ] || return 0
    \\  filtered+=("-Wno-error=unused-variable")
    \\  filtered+=("-Wno-error=unused-but-set-variable")
    \\  filtered+=("-Wno-error=switch")
    \\  filtered+=("-Wno-error=shorten-64-to-32")
    \\  filtered+=("-Wno-error=implicit-int-conversion")
    \\  filtered+=("-Wno-error=constant-conversion")
    \\}
    \\
    \\if [ "$(uname -s 2>/dev/null)" = "Darwin" ] && [ "${ROSETTE_MACOS_COMPAT_ENABLE:-auto}" != "0" ]; then
    \\  __rosette_add_macos_compat_header "$macos_shim_root/shims/macos/compiler_compat.h"
    \\  __rosette_add_macos_compat_header "$macos_shim_root/shims/macos/posix_compat.h"
    \\  __rosette_add_macos_compat_header "$macos_shim_root/shims/macos/endian.h"
    \\  __rosette_add_macos_compat_header "$macos_shim_root/shims/rosette/cpu_feature_probe.h"
    \\fi
    \\if [ "$target_x86" = "1" ] && [ "${ROSETTE_X86_INTRINSICS_COMPAT_ENABLE:-auto}" != "0" ] && [ -f "$x86_compat_header" ]; then
    \\  filtered+=("-include" "$x86_compat_header")
    \\fi
    \\while [ "$#" -gt 0 ]; do
    \\  arg="$1"
    \\  shift
    \\  case "$arg" in
    \\    -I|-isystem|-iquote|-idirafter)
    \\      if [ "$#" -gt 0 ]; then
    \\        path="$1"
    \\        shift
    \\        if [ "$target_x86" = "1" ] && __rosette_path_has_x86_intrinsic_shadow "$path"; then
    \\          continue
    \\        fi
    \\        filtered+=("$arg" "$path")
    \\      else
    \\        filtered+=("$arg")
    \\      fi
    \\      ;;
    \\    -I*)
    \\      path="${arg#-I}"
    \\      if [ "$target_x86" = "1" ] && __rosette_path_has_x86_intrinsic_shadow "$path"; then
    \\        continue
    \\      fi
    \\      filtered+=("$arg")
    \\      ;;
    \\    -isystem*|-iquote*|-idirafter*)
    \\      case "$arg" in
    \\        -isystem*) path="${arg#-isystem}" ;;
    \\        -iquote*) path="${arg#-iquote}" ;;
    \\        -idirafter*) path="${arg#-idirafter}" ;;
    \\      esac
    \\      path="${path#=}"
    \\      if [ "$target_x86" = "1" ] && [ -n "$path" ] && __rosette_path_has_x86_intrinsic_shadow "$path"; then
    \\        continue
    \\      fi
    \\      filtered+=("$arg")
    \\      ;;
    \\    *)
    \\      filtered+=("$arg")
    \\      ;;
    \\  esac
    \\done
    \\__rosette_add_macos_warning_compat_flags
    \\
    \\# rosette-c-fix pass: pre-apply narrowing casts to C/C++/ObjC source files
    \\rosette_fix_bin="${ROSETTE_C_FIX_BIN:-$HOME/.rosette/bin/rosette-c-fix}"
    \\if [ "${ROSETTE_C_FIX_ENABLE:-auto}" != "0" ] && [ -x "$rosette_fix_bin" ]; then
    \\  for src_file in "${filtered[@]}"; do
    \\    case "$src_file" in
    \\      *.c|*.cc|*.cpp|*.cxx|*.m|*.mm)
    \\        "$rosette_fix_bin" --in-place "$src_file" 2>/dev/null || true
    \\        ;;
    \\    esac
    \\  done
    \\fi
    \\
    \\exec "$compiler" "${filtered[@]}"
    \\
;

const arch_backend_script =
    \\#!/bin/sh
    \\# Generated by Rosette. Standalone arch handoff router.
    \\set +e
    \\
    \\orig_args="$*"
    \\case "${1:-}" in
    \\  -x86_64)
    \\    shift
    \\    ;;
    \\  -arch)
    \\    if [ "${2:-}" = "x86_64" ]; then
    \\      shift 2
    \\    else
    \\      exec /usr/bin/arch "$@"
    \\    fi
    \\    ;;
    \\  *)
    \\    exec /usr/bin/arch "$@"
    \\    ;;
    \\esac
    \\
    \\target="${1:-}"
    \\if [ -z "$target" ]; then
    \\  exec /usr/bin/arch $orig_args
    \\fi
    \\shift
    \\
    \\route_root="${ROSETTE_TRACE_ROOT:-${ROSETTE_ROUTE_ROOT:-${ROSETTE_CALLER_CWD:-$PWD}}}"
    \\export ROSETTE_ROUTE_ROOT="$route_root"
    \\
    \\router_source=""
    \\router=""
    \\
    \\__rosette_try_source_router() {
    \\  __source_root="$1"
    \\  if [ -n "$__source_root" ] && [ -x "$__source_root/zig-out/bin/rosette-router" ]; then
    \\    router="$__source_root/zig-out/bin/rosette-router"
    \\    router_source="$2"
    \\    return 0
    \\  fi
    \\  return 1
    \\}
    \\
    \\if [ "${ROSETTE_ROUTER_FORCE:-0}" = "1" ]; then
    \\  router="${ROSETTE_ROUTER:-}"
    \\  if [ -n "$router" ] && [ -x "$router" ]; then
    \\    router_source="ROSETTE_ROUTER_FORCE"
    \\  else
    \\    router=""
    \\  fi
    \\fi
    \\
    \\if [ -z "$router" ]; then
    \\  __rosette_try_source_router "${ROSETTE_SOURCE_ROOT:-}" "ROSETTE_SOURCE_ROOT" || true
    \\fi
    \\if [ -z "$router" ] && [ -f "$HOME/.rosette/source-root" ]; then
    \\  IFS= read -r __rosette_source_root < "$HOME/.rosette/source-root" 2>/dev/null || __rosette_source_root=""
    \\  __rosette_try_source_router "$__rosette_source_root" "source-root" || true
    \\fi
    \\if [ -z "$router" ]; then
    \\  self_dir="$(CDPATH= cd "$(dirname "$0")" 2>/dev/null && pwd)"
    \\  if [ -x "$self_dir/rosette-router" ]; then
    \\    router="$self_dir/rosette-router"
    \\    router_source="sibling"
    \\  fi
    \\fi
    \\if [ -z "$router" ]; then
    \\  router="${ROSETTE_ROUTER:-}"
    \\  if [ -n "$router" ] && [ -x "$router" ]; then
    \\    router_source="ROSETTE_ROUTER"
    \\  else
    \\    router=""
    \\  fi
    \\fi
    \\if [ -z "$router" ] && [ -x "$HOME/.rosette/bin/rosette-router" ]; then
    \\  router="$HOME/.rosette/bin/rosette-router"
    \\  router_source="installed"
    \\fi
    \\
    \\trace_path="${ROSETTE_COMPAT_TRACE:-}"
    \\if [ -z "$trace_path" ]; then
    \\  mkdir -p "$route_root/.rosette" 2>/dev/null || true
    \\  trace_path="$route_root/.rosette/rosetta2-handoff.trace.log"
    \\fi
    \\
    \\{
    \\  printf '# Rosette arch handoff\n'
    \\  printf 'event = "arch_backend_enter"\n'
    \\  printf 'target = "%s"\n' "$target"
    \\  printf 'cwd = "%s"\n' "$PWD"
    \\  printf 'route_root = "%s"\n' "$route_root"
    \\  printf 'router = "%s"\n' "$router"
    \\  printf 'router_source = "%s"\n' "$router_source"
    \\  printf '\n'
    \\} >> "$trace_path" 2>/dev/null || true
    \\
    \\if [ ! -x "$router" ]; then
    \\  {
    \\    printf '# Rosette arch handoff\n'
    \\    printf 'event = "arch_backend_missing_router"\n'
    \\    printf 'target = "%s"\n' "$target"
    \\    printf '\n'
    \\  } >> "$trace_path" 2>/dev/null || true
    \\  exec /usr/bin/arch -x86_64 "$target" "$@"
    \\fi
    \\
    \\if [ "${ROSETTE_ARCH_DRY_RUN:-0}" = "1" ]; then
    \\  export ROSETTE_ROUTER="$router"
    \\  {
    \\    printf '# Rosette arch handoff\n'
    \\    printf 'event = "arch_backend_exec_router"\n'
    \\    printf 'mode = "diagnose"\n'
    \\    printf 'router = "%s"\n' "$router"
    \\    printf 'target = "%s"\n' "$target"
    \\    printf '\n'
    \\  } >> "$trace_path" 2>/dev/null || true
    \\  exec "$router" diagnose --prefer-intel --trace "$trace_path" "$target" "$@"
    \\fi
    \\
    \\export ROSETTE_ROUTER="$router"
    \\{
    \\  printf '# Rosette arch handoff\n'
    \\  printf 'event = "arch_backend_exec_router"\n'
    \\  printf 'mode = "run"\n'
    \\  printf 'router = "%s"\n' "$router"
    \\  printf 'target = "%s"\n' "$target"
    \\  printf '\n'
    \\} >> "$trace_path" 2>/dev/null || true
    \\exec "$router" run --prefer-intel --trace "$trace_path" "$target" "$@"
    \\
;

fn ensureCleanStateBackend(allocator: std.mem.Allocator, clean_state_path: []const u8) !void {
    try writeFilePath(allocator, clean_state_path, clean_state_backend_script);
    try chmodPath(allocator, clean_state_path, 0o755);
}

const clean_state_backend_script =
    \\#!/bin/sh
    \\# Generated by Rosette. Targeted cleanup for Rosette/Xenia helper hangs.
    \\set +e
    \\
    \\dry_run=0
    \\include_xenia=1
    \\quarantine=1
    \\zap_groups=1
    \\for arg in "$@"; do
    \\  case "$arg" in
    \\    --scan|--dry-run) dry_run=1 ;;
    \\    --no-xenia) include_xenia=0 ;;
    \\    --xenia) include_xenia=1 ;;
    \\    --no-quarantine) quarantine=0 ;;
    \\    --quarantine) quarantine=1 ;;
    \\    --no-groups|--no-process-groups) zap_groups=0 ;;
    \\    --groups|--process-groups) zap_groups=1 ;;
    \\    *)
    \\      echo "rosette-clean-state: unknown option: $arg" >&2
    \\      exit 2
    \\      ;;
    \\  esac
    \\done
    \\
    \\tmp="${TMPDIR:-/tmp}/rosette-clean-state.$$"
    \\trap 'rm -f "$tmp.ps" "$tmp.candidates"' EXIT INT TERM
    \\self_pgid="$(/bin/ps -o pgid= -p "$$" 2>/dev/null | /usr/bin/awk '{print $1}')"
    \\quarantine_path="${ROSETTE_PROCESS_QUARANTINE:-$HOME/.rosette/process-quarantine.log}"
    \\
    \\if ! /bin/ps -axo pid=,ppid=,pgid=,stat=,command= > "$tmp.ps" 2>/dev/null; then
    \\  echo "rosette-clean-state: failed to read process list" >&2
    \\  exit 1
    \\fi
    \\
    \\/usr/bin/awk -v self="$$" -v parent="$PPID" -v include_xenia="$include_xenia" '
    \\function lower(s) { return tolower(s) }
    \\{
    \\  pid=$1; ppid=$2; pgid=$3; stat=$4
    \\  cmd=$0
    \\  sub(/^[[:space:]]*[0-9]+[[:space:]]+[0-9]+[[:space:]]+[0-9]+[[:space:]]+[^[:space:]]+[[:space:]]+/, "", cmd)
    \\  lc=lower(cmd)
    \\  reason=""
    \\  if (pid <= 1 || pid == self || pid == parent || ppid == self) next
    \\  if (index(lc, "rosette-clean-state") > 0) next
    \\  if (include_xenia != 1 && index(lc, "xenia_canary.app/contents/macos/xenia_canary") > 0) next
    \\  if (index(lc, "rosette-shell compiler-sanitize") > 0) reason="Rosette compiler sanitizer"
    \\  else if (index(lc, "rosette-compiler-sanitize") > 0) reason="Rosette compiler sanitizer launcher"
    \\  else if (index(lc, "rosette-shell route-arch") > 0) reason="Rosette arch handoff"
    \\  else if (index(lc, "rosette-arch") > 0) reason="Rosette arch backend"
    \\  else if (index(lc, "rosette-shell detect") > 0) reason="Rosette project detector"
    \\  else if (index(lc, "rosette-shell clean-state") > 0) reason="stuck Rosette cleanup helper"
    \\  else if (index(lc, "rosette-shell recipe-shell") > 0) reason="Rosette make recipe shell"
    \\  else if (index(lc, "rosette-shell tool") > 0) reason="Rosette compiler/tool wrapper"
    \\  else if (index(lc, "rosette-router") > 0) reason="Rosette compatibility router"
    \\  else if (index(lc, "elf_processor") > 0) reason="Rosette ELF processor"
    \\  else if (index(lc, "rosette_assembler_runner") > 0) reason="Rosette assembler ABI runner"
    \\  else if (index(lc, "rosette_exe_runner") > 0) reason="Rosette EXE runner"
    \\  else if (index(lc, "rosette_mscoree_window_helper") > 0) reason="Rosette managed window helper"
    \\  else if (index(lc, "/usr/local/bin/rose") > 0) reason="legacy Rosette launcher"
    \\  else if (index(lc, "xenia-rosetta.") > 0) reason="Rosette Xenia handoff script"
    \\  else if (include_xenia == 1 && index(lc, "xenia_canary.app/contents/macos/xenia_canary") > 0) reason="Rosette-launched Xenia Canary"
    \\  if (reason != "") {
    \\    gsub(/\t/, " ", cmd)
    \\    printf "%s\t%s\t%s\t%s\t%s\t%s\n", pid, ppid, pgid, stat, reason, cmd
    \\  }
    \\}
    \\' "$tmp.ps" > "$tmp.candidates"
    \\
    \\count="$(/usr/bin/wc -l < "$tmp.candidates" | /usr/bin/tr -d ' ')"
    \\if [ "$count" = "0" ]; then
    \\  echo "rosette-clean-state: no matching live Rosette helpers"
    \\  exit 0
    \\fi
    \\
    \\echo "rosette-clean-state: found $count candidate process(es)"
    \\while IFS="$(printf '\t')" read -r pid ppid pgid stat reason cmd; do
    \\  [ -n "$pid" ] || continue
    \\  echo "candidate: pid=$pid ppid=$ppid pgid=$pgid stat=$stat reason=$reason"
    \\  echo "  command: $cmd"
    \\done < "$tmp.candidates"
    \\
    \\if [ "$dry_run" = "1" ]; then
    \\  echo "rosette-clean-state: dry-run only; no signals sent"
    \\  exit 0
    \\fi
    \\
    \\__rosette_alive() {
    \\  /bin/kill -0 "$1" 2>/dev/null
    \\}
    \\
    \\__rosette_signal_group() {
    \\  sig="$1"
    \\  pgid="$2"
    \\  reason="$3"
    \\  [ "$zap_groups" = "1" ] || return 0
    \\  [ -n "$pgid" ] || return 0
    \\  [ "$pgid" != "0" ] || return 0
    \\  [ "$pgid" != "1" ] || return 0
    \\  if [ -n "$self_pgid" ] && [ "$pgid" = "$self_pgid" ]; then
    \\    return 0
    \\  fi
    \\  if /bin/kill "-$sig" "-$pgid" 2>/dev/null; then
    \\    echo "rosette-clean-state: sent SIG$sig to pgid=$pgid reason=$reason"
    \\  fi
    \\}
    \\
    \\__rosette_signal_pid() {
    \\  sig="$1"
    \\  pid="$2"
    \\  reason="$3"
    \\  if /bin/kill "-$sig" "$pid" 2>/dev/null; then
    \\    echo "rosette-clean-state: sent SIG$sig to pid=$pid reason=$reason"
    \\  else
    \\    echo "rosette-clean-state: SIG$sig failed for pid=$pid reason=$reason" >&2
    \\  fi
    \\}
    \\
    \\__rosette_quarantine_survivor() {
    \\  pid="$1"
    \\  ppid="$2"
    \\  pgid="$3"
    \\  stat="$4"
    \\  reason="$5"
    \\  cmd="$6"
    \\  [ "$quarantine" = "1" ] || return 0
    \\  quarantine_dir="$(dirname "$quarantine_path" 2>/dev/null)"
    \\  [ -n "$quarantine_dir" ] && mkdir -p "$quarantine_dir" 2>/dev/null || true
    \\  {
    \\    printf '%s\tpid=%s\tppid=%s\tpgid=%s\tstat=%s\treason=%s\tcmd=%s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$pid" "$ppid" "$pgid" "$stat" "$reason" "$cmd"
    \\  } >> "$quarantine_path" 2>/dev/null || true
    \\}
    \\
    \\while IFS="$(printf '\t')" read -r pid ppid pgid stat reason cmd; do
    \\  [ -n "$pid" ] || continue
    \\  __rosette_signal_group TERM "$pgid" "$reason"
    \\  __rosette_signal_pid TERM "$pid" "$reason"
    \\done < "$tmp.candidates"
    \\
    \\/bin/sleep 0.25
    \\
    \\while IFS="$(printf '\t')" read -r pid ppid pgid stat reason cmd; do
    \\  [ -n "$pid" ] || continue
    \\  if __rosette_alive "$pid"; then
    \\    __rosette_signal_group KILL "$pgid" "$reason"
    \\    __rosette_signal_pid KILL "$pid" "$reason"
    \\  fi
    \\done < "$tmp.candidates"
    \\
    \\/bin/sleep 0.25
    \\survivors=0
    \\while IFS="$(printf '\t')" read -r pid ppid pgid stat reason cmd; do
    \\  [ -n "$pid" ] || continue
    \\  if __rosette_alive "$pid"; then
    \\    survivors=$((survivors + 1))
    \\    echo "survivor: pid=$pid ppid=$ppid pgid=$pgid stat=$stat reason=$reason"
    \\    echo "  command: $cmd"
    \\    case "$stat" in
    \\      *U*|*E*)
    \\        echo "  note: kernel-held state '$stat'; macOS may keep this until the kernel releases it or the machine reboots."
    \\        ;;
    \\      *)
    \\        if /bin/kill -STOP "$pid" 2>/dev/null; then
    \\          echo "  action: suspended survivor with SIGSTOP so it stops consuming userland time"
    \\        fi
    \\        if [ -x /usr/bin/renice ]; then
    \\          /usr/bin/renice 20 -p "$pid" >/dev/null 2>&1 && echo "  action: lowered survivor priority with renice +20"
    \\        fi
    \\        ;;
    \\    esac
    \\    __rosette_quarantine_survivor "$pid" "$ppid" "$pgid" "$stat" "$reason" "$cmd"
    \\  fi
    \\done < "$tmp.candidates"
    \\
    \\if [ "$survivors" -eq 0 ]; then
    \\  echo "rosette-clean-state: completed; no signaled candidates remain"
    \\else
    \\  echo "rosette-clean-state: signaled candidates, but $survivors survivor(s) remain"
    \\  if [ "$quarantine" = "1" ]; then
    \\    echo "rosette-clean-state: survivor ledger: $quarantine_path"
    \\  fi
    \\fi
    \\
;

const x86IntrinsicsCompatH =
    \\#ifndef ROSETTE_X86_INTRINSICS_COMPAT_H
    \\#define ROSETTE_X86_INTRINSICS_COMPAT_H
    \\
    \\/*
    \\ * Rosette x86 intrinsic compatibility header.
    \\ *
    \\ * When cross-compiling x86_64 code from a non-x86 host, certain
    \\ * compiler builtins may not be available.  This file provides
    \\ * portable fallback definitions using inline assembly.
    \\ *
    \\ * Each public definition is guarded by #ifndef so the compiler's own
    \\ * definition (when present) takes precedence. Some bundled projects provide
    \\ * their own compatibility macro later in the include graph, so keep Clang's
    \\ * macro-redefinition warning quiet for this translation unit while Rosette is
    \\ * acting as the injected compatibility layer.
    \\ */
    \\
    \\#ifdef __x86_64__
    \\
    \\#if defined(__clang__)
    \\#pragma clang diagnostic ignored "-Wmacro-redefined"
    \\#endif
    \\
    \\#ifndef __rosette_cpuid_count
    \\#define __rosette_cpuid_count(leaf, subleaf, eax, ebx, ecx, edx)       \
    \\    __asm__ __volatile__("cpuid\n"                                    \
    \\                         : "=a"(eax), "=b"(ebx), "=c"(ecx), "=d"(edx) \
    \\                         : "0"(leaf), "2"(subleaf))
    \\#endif
    \\
    \\#ifndef __cpuid
    \\#define __cpuid(leaf, eax, ebx, ecx, edx)                              \
    \\    __rosette_cpuid_count((leaf), 0, (eax), (ebx), (ecx), (edx))
    \\#endif
    \\
    \\#ifndef __cpuid_count
    \\#define __cpuid_count(leaf, subleaf, eax, ebx, ecx, edx)              \
    \\    __rosette_cpuid_count((leaf), (subleaf), (eax), (ebx), (ecx), (edx))
    \\#endif
    \\#endif
    \\
    \\#endif
    \\
;

fn ensureX86CompatHeader(allocator: std.mem.Allocator, include_dir: []const u8) !void {
    const header_path = try std.fs.path.join(allocator, &.{ include_dir, "x86_intrinsics_compat.h" });
    writeFilePath(allocator, header_path, x86IntrinsicsCompatH) catch |err| {
        std.debug.print("warning: could not write x86 compat header: {s}\n", .{@errorName(err)});
    };
}

fn ensureMacOSCompatHeaders(io: std.Io, allocator: std.mem.Allocator, include_dir: []const u8) !void {
    const source_root = try macOSCompatSourceRoot(io, allocator);
    if (source_root.len == 0) return;

    const headers = [_][]const u8{
        "shims/macos/compiler_compat.h",
        "shims/macos/posix_compat.h",
        "shims/macos/endian.h",
        "shims/macos/force_types.h",
        "shims/macos/stb_compat.h",
        "shims/rosette/cpu_feature_probe.h",
    };
    for (headers) |header| {
        const source_path = try std.fs.path.join(allocator, &.{ source_root, "include", header });
        const bytes = std.Io.Dir.cwd().readFileAlloc(io, source_path, allocator, .limited(256 * 1024)) catch continue;
        const dest_path = try std.fs.path.join(allocator, &.{ include_dir, header });
        try writeFilePath(allocator, dest_path, bytes);
    }
}

fn macOSCompatSourceRoot(io: std.Io, allocator: std.mem.Allocator) ![]const u8 {
    const configured = try currentSourceRoot(io, allocator);
    if (configured.len != 0 and macOSCompatSourceRootHasHeaders(allocator, configured)) return configured;

    const cwd = absolutePath(allocator, ".") catch "";
    if (cwd.len != 0 and macOSCompatSourceRootHasHeaders(allocator, cwd)) return cwd;

    return configured;
}

fn macOSCompatSourceRootHasHeaders(allocator: std.mem.Allocator, source_root: []const u8) bool {
    const marker = std.fs.path.join(allocator, &.{ source_root, "include", "shims", "macos", "compiler_compat.h" }) catch return false;
    return fileExists(allocator, marker);
}

fn resolveX86CompatHeaderPath() ?[]const u8 {
    const installed = getenvSlice("ROSETTE_X86_INTRINSICS_COMPAT") orelse return null;
    if (installed.len == 0) return null;
    return installed;
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
    std.debug.print("  rosette-clean-state --scan\n", .{});
    std.debug.print("  rosette-clean-state\n", .{});
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
    if (getenvSlice("ROSETTE_ROUTER_FORCE")) |force| {
        if (std.mem.eql(u8, force, "1")) {
            if (getenvSlice("ROSETTE_ROUTER")) |router_path| {
                if (canExecute(allocator, router_path) or fileExists(allocator, router_path)) {
                    return try allocator.dupe(u8, router_path);
                }
            }
        }
    }

    const source_root = currentSourceRoot(init.io, allocator) catch "";
    if (source_root.len != 0) {
        const from_source = try std.fs.path.join(allocator, &.{ source_root, "zig-out", "bin", "rosette-router" });
        if (canExecute(allocator, from_source) or fileExists(allocator, from_source)) return from_source;
    }

    const self_path = std.process.executablePathAlloc(init.io, allocator) catch "";
    if (self_path.len != 0) {
        if (std.fs.path.dirname(self_path)) |self_dir| {
            const sibling = try std.fs.path.join(allocator, &.{ self_dir, "rosette-router" });
            if (canExecute(allocator, sibling) or fileExists(allocator, sibling)) return sibling;
        }
    }

    const cwd_candidate = try std.fs.path.join(allocator, &.{ "zig-out", "bin", "rosette-router" });
    if (canExecute(allocator, cwd_candidate) or fileExists(allocator, cwd_candidate)) return cwd_candidate;

    if (getenvSlice("ROSETTE_ROUTER")) |router_path| {
        if (canExecute(allocator, router_path) or fileExists(allocator, router_path)) {
            return try allocator.dupe(u8, router_path);
        }
    }

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
    try appendFilteredLinuxArgs(io, &argv, allocator, tool_args, true);
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

fn runCompilerSanitizer(io: std.Io, allocator: std.mem.Allocator, compiler_argv: []const []const u8) !void {
    if (compiler_argv.len == 0) return error.EmptyArgv;

    // Scan for C/C++/ObjC source files and run rosette-c-fix on each
    {
        const fix_bin_env = std.c.getenv("ROSETTE_C_FIX_BIN");
        const rosette_dir_env = std.c.getenv("HOME");
        const default_fix_path = if (rosette_dir_env) |home|
            std.fs.path.join(allocator, &.{ std.mem.span(home), ".rosette", "bin", "rosette-c-fix" }) catch null
        else
            null;
        const fix_bin = if (fix_bin_env) |env| std.mem.span(env) else (default_fix_path orelse "rosette-c-fix");
        if (canExecute(allocator, fix_bin)) {
            const enable_env = std.c.getenv("ROSETTE_C_FIX_ENABLE");
            const enable = if (enable_env) |env| std.mem.span(env) else "auto";
            if (!std.mem.eql(u8, enable, "0")) {
                for (compiler_argv[1..]) |arg| {
                    const is_source = std.mem.endsWith(u8, arg, ".c") or
                        std.mem.endsWith(u8, arg, ".cc") or
                        std.mem.endsWith(u8, arg, ".cpp") or
                        std.mem.endsWith(u8, arg, ".cxx") or
                        std.mem.endsWith(u8, arg, ".m") or
                        std.mem.endsWith(u8, arg, ".mm");
                    if (is_source) {
                        const fix_argv = [_][]const u8{ fix_bin, "--in-place", arg };
                        _ = runArgvResult(io, &fix_argv) catch {};
                    }
                }
            }
        }
    }

    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);
    try argv.append(allocator, compiler_argv[0]);
    try appendSanitizedCompilerArgs(io, &argv, allocator, compiler_argv[1..], compilerArgsTargetX86(compiler_argv[1..]), false);
    try execArgvReplace(allocator, argv.items);
}

fn runZigCompiler(io: std.Io, allocator: std.mem.Allocator, zig_mode: []const u8, tool_args: []const []const u8) !u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);
    try argv.append(allocator, try resolveToolPath(allocator, "zig"));
    try argv.append(allocator, zig_mode);
    try argv.append(allocator, "-target");
    try argv.append(allocator, "x86_64-linux-gnu");
    try argv.append(allocator, "-Wno-nullability-completeness");
    try appendProjectIncludeArgs(io, &argv, allocator);
    try appendSanitizedCompilerArgs(io, &argv, allocator, tool_args, true, false);
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

fn includeDirShadowsX86Intrinsics(io: std.Io, path: []const u8) bool {
    return project_includes.containsX86IntrinsicShadow(io, path);
}

fn appendFilteredLinuxArgs(
    io: std.Io,
    argv: *std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
    tool_args: []const []const u8,
    strip_ld_debug: bool,
) !void {
    try appendSanitizedCompilerArgs(io, argv, allocator, tool_args, true, strip_ld_debug);
}

fn appendSanitizedCompilerArgs(
    io: std.Io,
    argv: *std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
    tool_args: []const []const u8,
    target_x86: bool,
    strip_ld_debug: bool,
) !void {
    try appendMacOSCompatIncludes(allocator, argv);

    // Inject x86 intrinsic compat header when targeting x86, to bridge
    // builtins that may be absent when cross-compiling from a non-x86 host
    // (e.g. __cpuid_count on Apple Clang for ARM64). The installed Bash
    // launcher provides the default ~/.rosette path; this legacy Zig path
    // consumes only explicit environment configuration to avoid owned argv
    // lifetime hazards.
    if (target_x86) {
        if (resolveX86CompatHeaderPath()) |header_path| {
            try argv.append(allocator, "-include");
            try argv.append(allocator, header_path);
        }
    }

    var i: usize = 0;
    while (i < tool_args.len) : (i += 1) {
        const arg = tool_args[i];
        if (strip_ld_debug and std.mem.eql(u8, arg, "-g")) continue;
        if (std.mem.eql(u8, arg, "-z") and i + 1 < tool_args.len and std.mem.eql(u8, tool_args[i + 1], "noexecstack")) {
            i += 1;
            continue;
        }
        // Strip include paths that shadow native x86 intrinsic headers
        // (for example a bundled emmintrin.h). Keep bridge entry headers like
        // vex2neon.h locatable when a project explicitly includes them.
        if (target_x86 and isIncludeFlag(arg) != null) {
            if (i + 1 < tool_args.len and includeDirShadowsX86Intrinsics(io, tool_args[i + 1])) {
                i += 1;
                continue;
            }
        }
        if (target_x86) {
            if (joinedIncludePath(arg)) |path| {
                if (includeDirShadowsX86Intrinsics(io, path)) continue;
            }
        }
        try argv.append(allocator, arg);
    }
    try appendMacOSWarningCompatFlags(argv, allocator);
}

fn appendMacOSCompatIncludes(allocator: std.mem.Allocator, argv: *std.ArrayList([]const u8)) !void {
    if (builtin.target.os.tag != .macos) return;
    if (getenvSlice("ROSETTE_MACOS_COMPAT_ENABLE")) |value| {
        if (isFalseEnvValue(value)) return;
    }

    const root = try macOSCompatIncludeRoot(allocator);
    const headers = [_][]const u8{
        "shims/macos/compiler_compat.h",
        "shims/macos/posix_compat.h",
        "shims/macos/endian.h",
        "shims/rosette/cpu_feature_probe.h",
    };
    for (headers) |header| {
        const header_path = try std.fs.path.join(allocator, &.{ root, header });
        if (!fileExists(allocator, header_path)) continue;
        try argv.append(allocator, "-include");
        try argv.append(allocator, header_path);
    }
}

fn macOSCompatIncludeRoot(allocator: std.mem.Allocator) ![]const u8 {
    if (getenvSlice("ROSETTE_MACOS_COMPAT_INCLUDE_ROOT")) |root| {
        if (root.len != 0) return try allocator.dupe(u8, root);
    }
    const home = try homeDir(allocator);
    return try std.fs.path.join(allocator, &.{ home, ".rosette", "include" });
}

const macos_warning_compat_flags = [_][]const u8{
    "-Wno-error=unused-variable",
    "-Wno-error=unused-but-set-variable",
    "-Wno-error=switch",
    "-Wno-error=shorten-64-to-32",
    "-Wno-error=implicit-int-conversion",
    "-Wno-error=constant-conversion",
};

fn appendMacOSWarningCompatFlags(argv: *std.ArrayList([]const u8), allocator: std.mem.Allocator) !void {
    if (builtin.target.os.tag != .macos) return;
    if (getenvSlice("ROSETTE_MACOS_WARNING_COMPAT_ENABLE")) |value| {
        if (isFalseEnvValue(value)) return;
    }
    for (macos_warning_compat_flags) |flag| {
        try argv.append(allocator, flag);
    }
}

fn isIncludeFlag(arg: []const u8) ?[]const u8 {
    const flags = [_][]const u8{ "-I", "-isystem", "-iquote", "-idirafter" };
    for (flags) |flag| {
        if (std.mem.eql(u8, arg, flag)) return flag;
    }
    return null;
}

fn joinedIncludePath(arg: []const u8) ?[]const u8 {
    if (std.mem.startsWith(u8, arg, "-I") and arg.len > 2) return arg[2..];
    const joined_flags = [_][]const u8{ "-isystem", "-iquote", "-idirafter" };
    for (joined_flags) |flag| {
        if (std.mem.startsWith(u8, arg, flag) and arg.len > flag.len) {
            var path = arg[flag.len..];
            if (path.len != 0 and path[0] == '=') path = path[1..];
            if (path.len != 0) return path;
        }
    }
    return null;
}

fn compilerArgsTargetX86(args: []const []const u8) bool {
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-arch") and i + 1 < args.len and targetNameIsX86(args[i + 1])) return true;
        if (std.mem.eql(u8, arg, "-target") and i + 1 < args.len and targetNameIsX86(args[i + 1])) return true;
        if (std.mem.startsWith(u8, arg, "--target=") and targetNameIsX86(arg["--target=".len..])) return true;
        if (std.mem.startsWith(u8, arg, "-target") and arg.len > "-target".len and targetNameIsX86(arg["-target".len..])) return true;
    }
    return false;
}

fn targetNameIsX86(value: []const u8) bool {
    return containsIgnoreCase(value, "x86_64") or
        containsIgnoreCase(value, "amd64") or
        containsIgnoreCase(value, "i386") or
        containsIgnoreCase(value, "i486") or
        containsIgnoreCase(value, "i586") or
        containsIgnoreCase(value, "i686");
}

fn appendProjectIncludeArgs(io: std.Io, argv: *std.ArrayList([]const u8), allocator: std.mem.Allocator) !void {
    if (!projectIncludeCompatEnabled()) return;
    const root = projectIncludeRoot(allocator) catch return;
    var dirs = project_includes.discoverIncludeDirs(io, allocator, root) catch return;
    defer {
        for (dirs.items) |dir| allocator.free(dir);
        dirs.deinit(allocator);
    }

    for (dirs.items) |dir| {
        // Same intrinsic-shadow filtering as appendSanitizedCompilerArgs.
        if (includeDirShadowsX86Intrinsics(io, dir)) continue;
        try argv.append(allocator, "-I");
        try argv.append(allocator, dir);
    }
}

fn projectIncludeCompatEnabled() bool {
    if (getenvSlice("ROSETTE_PROJECT_INCLUDE_COMPAT")) |value| {
        return !isFalseEnvValue(value);
    }
    const value = getenvSlice("ROSETTE_THIRD_PARTY_INCLUDE_COMPAT") orelse return true;
    return !isFalseEnvValue(value);
}

fn projectIncludeRoot(allocator: std.mem.Allocator) ![]const u8 {
    const candidates = [_]?[]const u8{
        getenvSlice("ROSETTE_PROJECT_INCLUDE_ROOT"),
        getenvSlice("ROSETTE_THIRD_PARTY_INCLUDE_ROOT"),
        getenvSlice("ROSETTE_ROUTE_ROOT"),
        getenvSlice("ROSETTE_CALLER_CWD"),
        getenvSlice("ROSETTE_PROJECT_ROOT"),
        getenvSlice("PWD"),
    };

    for (candidates) |candidate| {
        const raw = candidate orelse continue;
        if (raw.len == 0) continue;
        return absolutePath(allocator, raw) catch try allocator.dupe(u8, raw);
    }
    return absolutePath(allocator, ".") catch try allocator.dupe(u8, ".");
}

fn isFalseEnvValue(value: []const u8) bool {
    return std.ascii.eqlIgnoreCase(value, "0") or
        std.ascii.eqlIgnoreCase(value, "off") or
        std.ascii.eqlIgnoreCase(value, "false") or
        std.ascii.eqlIgnoreCase(value, "no");
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

fn execArgvReplace(allocator: std.mem.Allocator, argv: []const []const u8) !void {
    if (argv.len == 0) return error.EmptyArgv;

    // Pre-flight: verify the binary exists and is executable.
    if (!canExecute(allocator, argv[0])) {
        std.debug.print("rosette-shell: cannot exec {s} — not found or not executable\n", .{argv[0]});
        std.process.exit(127);
    }

    var argv_z: std.ArrayList(?[*:0]const u8) = .empty;
    defer argv_z.deinit(allocator);

    const path_z = try allocator.dupeZ(u8, argv[0]);
    try argv_z.append(allocator, path_z.ptr);
    for (argv[1..]) |arg| {
        const arg_z = try allocator.dupeZ(u8, arg);
        try argv_z.append(allocator, arg_z.ptr);
    }
    try argv_z.append(allocator, null);

    // Build a clean environment: strip Rosette vars and DYLD_INSERT_LIBRARIES
    // to prevent recursive interception or arch-mismatch dylib hangs.
    var clean_env: std.ArrayList(?[*:0]const u8) = .empty;
    defer clean_env.deinit(allocator);

    {
        var i: usize = 0;
        while (std.c.environ[i]) |entry| : (i += 1) {
            const entry_str = std.mem.sliceTo(entry, 0);
            const eq_pos = std.mem.indexOfScalar(u8, entry_str, '=') orelse {
                const e = try allocator.dupeZ(u8, entry_str);
                try clean_env.append(allocator, e.ptr);
                continue;
            };
            const var_name = entry_str[0..eq_pos];
            if (std.mem.startsWith(u8, var_name, "ROSETTE_")) continue;
            if (std.mem.eql(u8, var_name, "DYLD_INSERT_LIBRARIES")) continue;
            const e = try allocator.dupeZ(u8, entry_str);
            try clean_env.append(allocator, e.ptr);
        }
    }
    try clean_env.append(allocator, null);

    if (getenvSlice("ROSETTE_SANITIZER_TRACE")) |_| {
        std.debug.print("rosette-shell: exec {s}", .{argv[0]});
        for (argv[1..]) |a| std.debug.print(" {s}", .{a});
        std.debug.print("\n", .{});
    }

    // Use fork+exec with timeout so the parent survives and can diagnose.
    // Direct execve can hang at kernel level if Rosette's kext blocks.
    execForkWait(argv_z.items, path_z.ptr, clean_env.items);
}

fn monotonicMs() u64 {
    var ts: c.struct_timespec = undefined;
    if (c.clock_gettime(0, &ts) == 0) {
        // clock_gettime with CLOCK_MONOTONIC = 0 on most systems
        return @as(u64, @intCast(ts.tv_sec)) * 1000 + @as(u64, @intCast(@divTrunc(ts.tv_nsec, @as(c_long, 1_000_000))));
    }
    // Fallback: use gettimeofday
    var tv: c.struct_timeval = undefined;
    _ = c.gettimeofday(&tv, null);
    return @as(u64, @intCast(tv.tv_sec)) * 1000 + @as(u64, @intCast(@divTrunc(tv.tv_usec, @as(c_int, 1000))));
}

fn execForkWait(argv: [](?[*:0]const u8), path: [*:0]const u8, env: [](?[*:0]const u8)) noreturn {
    const pid = c.fork();
    switch (pid) {
        -1 => {
            const err = currentErrno();
            std.debug.print("rosette-shell: fork failed (errno={d}: {s})\n", .{ err, errnoName(err) });
            std.process.exit(127);
        },
        0 => {
            // Child: exec with clean environment.
            _ = c.execve(path, @ptrCast(argv.ptr), @ptrCast(env.ptr));
            // Only reachable if execve fails.
            const err = currentErrno();
            std.debug.print("rosette-shell: child execve({s}) failed (errno={d}: {s})\n", .{
                std.mem.sliceTo(path, 0), err, errnoName(err),
            });
            c._exit(127);
        },
        else => {
            // Parent: wait with timeout.
            const timeout_ms: u64 = 30000;
            const poll_interval_ns: u64 = 50 * std.time.ns_per_ms;
            var deadline: ?u64 = null;

            if (getenvSlice("ROSETTE_SANITIZER_TIMEOUT_MS")) |timeout_str| {
                if (std.fmt.parseUnsigned(u64, timeout_str, 10)) |parsed| {
                    deadline = if (parsed > 0) monotonicMs() + parsed else null;
                } else |_| {}
            }
            if (deadline == null) deadline = monotonicMs() + timeout_ms;
            const deadline_ms = deadline.?;

            var status: i32 = 0;
            while (true) {
                const now_ms = monotonicMs();
                if (now_ms >= deadline_ms) {
                    // Timeout — kill child and report.
                    _ = c.kill(pid, c.SIGKILL);
                    // Small grace for kill to take effect.
                    _ = c.usleep(100_000);
                    _ = c.kill(pid, c.SIGKILL);
                    std.debug.print("rosette-shell: {s} timed out after {}ms — killed\n", .{
                        std.mem.sliceTo(path, 0), now_ms - (deadline_ms - timeout_ms),
                    });

                    // Print diagnostics about the stuck process.
                    _ = tryResolveProcPath(pid);
                    _ = tryKmemStack(pid);

                    std.process.exit(124);
                }

                const rc = c.waitpid(pid, &status, c.WNOHANG);
                if (rc == pid) {
                    // Child exited.
                    if (c.WIFEXITED(status)) std.process.exit(@intCast(c.WEXITSTATUS(status)));
                    if (c.WIFSIGNALED(status)) {
                        const sig = c.WTERMSIG(status);
                        std.debug.print("rosette-shell: {s} killed by signal {d}\n", .{
                            std.mem.sliceTo(path, 0), sig,
                        });
                        std.process.exit(128 + @as(u8, @intCast(sig)));
                    }
                    std.debug.print("rosette-shell: {s} exited abnormally (status={x})\n", .{
                        std.mem.sliceTo(path, 0), status,
                    });
                    std.process.exit(1);
                } else if (rc == -1) {
                    const err = currentErrno();
                    std.debug.print("rosette-shell: waitpid failed (errno={d}: {s})\n", .{ err, errnoName(err) });
                    std.process.exit(127);
                }
                // rc == 0: child still running, poll again.
                _ = c.usleep(@intCast(poll_interval_ns / std.time.ns_per_us));
            }
        },
    }
}

fn tryResolveProcPath(pid: i32) bool {
    // Attempt to read the child's cwd via proc_regionfilename or proc_pidpath.
    var path_buf: [4096]u8 = undefined;
    const len = c.proc_regionfilename(pid, 0, &path_buf, @as(u32, @intCast(path_buf.len)));
    if (len > 0) {
        const path_slice = path_buf[0..@intCast(len)];
        std.debug.print("rosette-shell: stuck pid {d} region: {s}\n", .{ pid, path_slice });
        return true;
    }
    return false;
}

fn tryKmemStack(pid: i32) bool {
    _ = pid;
    return false;
}

fn runArgvResult(io: std.Io, argv: []const []const u8) !u8 {
    return process_guard.runExitCode(io, .{
        .argv = argv,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
        .label = "rosette-shell",
        .timeout_ms = process_guard.timeoutFromEnv(null),
        .isolate_process_group = false,
        .signal_policy = .child_only,
    }) catch |err| {
        if (argv.len > 0) {
            std.debug.print("rosette-shell: guarded spawn failed for {s}: {s}\n", .{ argv[0], @errorName(err) });
        } else {
            std.debug.print("rosette-shell: guarded spawn failed: {s}\n", .{@errorName(err)});
        }
        std.process.exit(127);
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

fn shellSingleQuoted(allocator: std.mem.Allocator, value: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try appendShellQuoted(&out, allocator, value);
    return out.items;
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
        defer allocator.free(path_z);
        if (c.mkdir(path_z.ptr, 0o755) != 0) {
            if (c.access(path_z.ptr, 0) != 0) return error.MakePathFailed;
        }
    }
}

fn writeFilePath(allocator: std.mem.Allocator, path: []const u8, data: []const u8) !void {
    const parent = std.fs.path.dirname(path);
    if (parent) |dir| try makePathRecursive(allocator, dir);
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);
    const fp = c.fopen(path_z.ptr, "wb");
    if (fp == null) return error.OpenFailed;
    defer _ = c.fclose(fp);

    if (data.len != 0) {
        const wrote = c.fwrite(data.ptr, 1, data.len, fp);
        if (wrote != data.len) return error.WriteFailed;
    }
}

fn appendFilePath(allocator: std.mem.Allocator, path: []const u8, data: []const u8) !void {
    const parent = std.fs.path.dirname(path);
    if (parent) |dir| try makePathRecursive(allocator, dir);
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);
    const fp = c.fopen(path_z.ptr, "ab");
    if (fp == null) return error.OpenFailed;
    defer _ = c.fclose(fp);

    if (data.len != 0) {
        const wrote = c.fwrite(data.ptr, 1, data.len, fp);
        if (wrote != data.len) return error.WriteFailed;
    }
}

fn chmodPath(allocator: std.mem.Allocator, path: []const u8, mode: u16) !void {
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);
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

    std.debug.print("[DYLIB] Compiling dylib from source: {s}\n", .{source_path});
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

    std.debug.print("[DYLIB] Spawning zig cc with timeout (30s)\n", .{});
    std.debug.print("[DYLIB] Command: {s}\n", .{try std.mem.join(allocator, " ", argv.items)});

    // Use process_guard with a 30-second timeout for compilation
    const code = process_guard.runExitCode(init.io, .{
        .argv = argv.items,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
        .label = "zig-cc-dylib",
        .timeout_ms = 30000, // 30 second timeout
        .kill_grace_ms = 5000, // 5 second grace period
        .isolate_process_group = true,
        .signal_policy = .process_group,
    }) catch |err| {
        std.debug.print("[DYLIB] Error: failed to compile rosette-exec.dylib: {s}\n", .{@errorName(err)});
        std.debug.print("[DYLIB] Attempting cleanup of any zig processes...\n", .{});
        pid_manager.killProcessesMatchingPattern(allocator, "zig") catch {};
        std.debug.print("  elf_processor binary installed, DYLD interposition not available\n", .{});
        return;
    };

    std.debug.print("[DYLIB] zig cc exited with code: {d}\n", .{code});

    if (code != 0) {
        std.debug.print("[DYLIB] Warning: zig cc returned exit code {d} for dylib compilation\n", .{code});
        std.debug.print("[DYLIB] Attempting cleanup of any zig processes...\n", .{});
        pid_manager.killProcessesMatchingPattern(allocator, "zig") catch {};
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

fn copyMachoProcessor(init: std.process.Init, allocator: std.mem.Allocator, source_root: []const u8, dest_path: []const u8) !void {
    const candidates = [_][]const u8{
        try std.fs.path.join(allocator, &.{ source_root, "zig-out", "bin", "macho_processor" }),
        try std.fs.path.join(allocator, &.{ source_root, "..", "..", "MacOS", "macho_processor" }),
        try std.fs.path.join(allocator, &.{ source_root, "macho_processor" }),
    };

    for (candidates) |candidate| {
        if (fileExists(allocator, candidate) and canExecute(allocator, candidate)) {
            try copyFile(init, allocator, candidate, dest_path, "macho_processor");
            _ = chmodPath(allocator, dest_path, 0o755) catch {};
            return;
        }
    }
    std.debug.print("rosette-shell: warning: macho_processor binary not found; build with 'make macho-processor-build' first\n", .{});
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

fn copyRosetteCFix(init: std.process.Init, allocator: std.mem.Allocator, source_root: []const u8, dest_path: []const u8) !void {
    const candidates = [_][]const u8{
        try std.fs.path.join(allocator, &.{ source_root, "zig-out", "bin", "rosette-c-fix" }),
        try std.fs.path.join(allocator, &.{ source_root, "..", "..", "MacOS", "rosette-c-fix" }),
        try std.fs.path.join(allocator, &.{ source_root, "rosette-c-fix" }),
    };

    for (candidates) |candidate| {
        if (fileExists(allocator, candidate) and canExecute(allocator, candidate)) {
            try copyFile(init, allocator, candidate, dest_path, "rosette-c-fix");
            _ = chmodPath(allocator, dest_path, 0o755) catch {};
            return;
        }
    }
    std.debug.print("rosette-shell: warning: rosette-c-fix binary not found; build with 'zig build' first\n", .{});
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
    defer allocator.free(path_z);
    if (c.unlink(path_z.ptr) != 0 and c.access(path_z.ptr, 0) == 0) return error.UnlinkFailed;
}

fn rmdirIfEmpty(allocator: std.mem.Allocator, path: []const u8) !void {
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);
    if (c.rmdir(path_z.ptr) != 0 and c.access(path_z.ptr, 0) == 0) return error.RmdirFailed;
}

fn fileExists(allocator: std.mem.Allocator, path: []const u8) bool {
    const path_z = allocator.dupeZ(u8, path) catch return false;
    defer allocator.free(path_z);
    return c.access(path_z.ptr, 0) == 0;
}

fn canExecute(allocator: std.mem.Allocator, path: []const u8) bool {
    const path_z = allocator.dupeZ(u8, path) catch return false;
    defer allocator.free(path_z);
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

test "config upgrade adds strict compat keys without replacing existing values" {
    const toml =
        \\[compat]
        \\allow_rosetta2_fallback = false
        \\trace = true
    ;
    const upgraded = (try upgradeConfigText(std.testing.allocator, toml)).?;
    defer std.testing.allocator.free(upgraded);
    try std.testing.expect(containsIgnoreCase(upgraded, "allow_rosetta2_fallback = false"));
    try std.testing.expect(containsIgnoreCase(upgraded, "strict = false"));
    try std.testing.expect(containsIgnoreCase(upgraded, "abort_on_fallback = false"));
    try std.testing.expect(containsIgnoreCase(upgraded, "abort_on_unsupported = false"));
}

test "config upgrade leaves complete compat section unchanged" {
    const toml =
        \\[compat]
        \\allow_rosetta2_fallback = false
        \\strict = true
        \\abort_on_fallback = true
        \\abort_on_unsupported = true
        \\trace = true
    ;
    try std.testing.expect((try upgradeConfigText(std.testing.allocator, toml)) == null);
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
    try std.testing.expect(containsIgnoreCase(snippet, "__rosette_detect_project_with_timeout"));
    try std.testing.expect(containsIgnoreCase(snippet, "ROSETTE_DIRECT_ELF_FULL_DETECT"));
    try std.testing.expect(containsIgnoreCase(snippet, "ROSETTE_DIRECT_ELF_DETECT_TIMEOUT_MS"));
    try std.testing.expect(containsIgnoreCase(snippet, "ROSETTE_X86_INTRINSICS_COMPAT"));
    try std.testing.expect(containsIgnoreCase(snippet, "ROSETTE_SHELL_DISABLE=1 command make"));
    try std.testing.expect(containsIgnoreCase(snippet, "__rosette_should_probe_direct_elf"));
    try std.testing.expect(containsIgnoreCase(snippet, "functions[$__rosette_cmd]"));
    try std.testing.expect(containsIgnoreCase(snippet, "ROSETTE_ENABLE_DYLD_INTERPOSE:-0"));
    try std.testing.expect(containsIgnoreCase(snippet, "__rosette_strip_dyld_interposer"));
}

test "arch route parser handles x86_64 short form" {
    const args = [_][]const u8{ "-x86_64", "/bin/bash", "-c", "true" };
    const route = parseArchRoute(&args).?;
    try std.testing.expectEqualStrings("/bin/bash", route.target);
    try std.testing.expectEqual(@as(usize, 2), route.target_args.len);
    try std.testing.expectEqualStrings("-c", route.target_args[0]);
    try std.testing.expectEqualStrings("true", route.target_args[1]);
}

test "arch route parser handles x86_64 arch flag form" {
    const args = [_][]const u8{ "-arch", "x86_64", "/usr/local/bin/brew", "--prefix" };
    const route = parseArchRoute(&args).?;
    try std.testing.expectEqualStrings("/usr/local/bin/brew", route.target);
    try std.testing.expectEqual(@as(usize, 1), route.target_args.len);
    try std.testing.expectEqualStrings("--prefix", route.target_args[0]);
}

test "arch route parser ignores plain and non-x86 requests" {
    const plain_args = [_][]const u8{"arch"};
    const arm_args = [_][]const u8{ "-arm64", "/bin/echo" };
    try std.testing.expect(parseArchRoute(&plain_args) == null);
    try std.testing.expect(parseArchRoute(&arm_args) == null);
}

test "bash env snippet routes x86 arch only" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const snippet = try buildBashEnvSnippet(arena.allocator(), "/tmp/rosette/bin/rosette-shell");
    try std.testing.expect(containsIgnoreCase(snippet, "rosette-arch"));
    try std.testing.expect(containsIgnoreCase(snippet, "ROSETTE_ARCH_BACKEND"));
    try std.testing.expect(containsIgnoreCase(snippet, "ROSETTE_CALLER_CWD"));
    try std.testing.expect(containsIgnoreCase(snippet, "-x86_64"));
    try std.testing.expect(containsIgnoreCase(snippet, "-arch"));
    try std.testing.expect(containsIgnoreCase(snippet, "command /usr/bin/arch"));
    try std.testing.expect(containsIgnoreCase(snippet, "ROSETTE_USER_BASH_ENV"));
}

test "bash env snippet enables scoped project include compatibility" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const snippet = try buildBashEnvSnippet(arena.allocator(), "/tmp/rosette/bin/rosette-shell");
    try std.testing.expect(containsIgnoreCase(snippet, "ROSETTE_COMPILER_SANITIZER"));
    try std.testing.expect(containsIgnoreCase(snippet, "ROSETTE_X86_INTRINSICS_COMPAT"));
    try std.testing.expect(containsIgnoreCase(snippet, "CMAKE_C_COMPILER_LAUNCHER"));
    try std.testing.expect(containsIgnoreCase(snippet, "CMAKE_CXX_COMPILER_LAUNCHER"));
    try std.testing.expect(containsIgnoreCase(snippet, "ROSETTE_PROJECT_INCLUDE_COMPAT"));
    try std.testing.expect(containsIgnoreCase(snippet, "ROSETTE_PROJECT_INCLUDE_ROOT"));
    try std.testing.expect(containsIgnoreCase(snippet, "__rosette_apply_project_include_compat"));
    try std.testing.expect(containsIgnoreCase(snippet, "ROSETTE_THIRD_PARTY_INCLUDE_COMPAT"));
    try std.testing.expect(containsIgnoreCase(snippet, "third_party"));
    try std.testing.expect(containsIgnoreCase(snippet, "vendor"));
    try std.testing.expect(containsIgnoreCase(snippet, "external"));
    try std.testing.expect(containsIgnoreCase(snippet, "CPATH"));
    try std.testing.expect(containsIgnoreCase(snippet, "ROSETTE_PROJECT_INCLUDE_DIRS"));
    try std.testing.expect(!containsIgnoreCase(snippet, "Wno-error=shorten-64-to-32"));
    try std.testing.expect(!containsIgnoreCase(snippet, "capstone_compat.h"));
}

test "compiler sanitizer strips x86 intrinsic shadows but keeps bridge entry headers" {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(std.testing.allocator);

    const allocator = std.testing.allocator;
    const test_root = try std.fmt.allocPrint(allocator, "/tmp/rosette-compiler-sanitize-{d}", .{c.getpid()});
    defer allocator.free(test_root);

    const shadow_dir = try std.fs.path.join(allocator, &.{ test_root, "AvxToNeon" });
    defer allocator.free(shadow_dir);
    const bridge_dir = try std.fs.path.join(allocator, &.{ test_root, "vex2NEON" });
    defer allocator.free(bridge_dir);
    const safe_dir = try std.fs.path.join(allocator, &.{ test_root, "zstd" });
    defer allocator.free(safe_dir);
    const shadow_header = try std.fs.path.join(allocator, &.{ shadow_dir, "emmintrin.h" });
    defer allocator.free(shadow_header);
    const bridge_header = try std.fs.path.join(allocator, &.{ bridge_dir, "vex2neon.h" });
    defer allocator.free(bridge_header);
    const safe_header = try std.fs.path.join(allocator, &.{ safe_dir, "zstd.h" });
    defer allocator.free(safe_header);
    const bridge_joined = try std.fmt.allocPrint(allocator, "-I{s}", .{bridge_dir});
    defer allocator.free(bridge_joined);
    const safe_joined = try std.fmt.allocPrint(allocator, "-I{s}", .{safe_dir});
    defer allocator.free(safe_joined);

    try writeFilePath(allocator, shadow_header, "");
    try writeFilePath(allocator, bridge_header, "");
    try writeFilePath(allocator, safe_header, "");
    defer {
        unlinkIfExists(allocator, shadow_header) catch {};
        unlinkIfExists(allocator, bridge_header) catch {};
        unlinkIfExists(allocator, safe_header) catch {};
        rmdirIfEmpty(allocator, shadow_dir) catch {};
        rmdirIfEmpty(allocator, bridge_dir) catch {};
        rmdirIfEmpty(allocator, safe_dir) catch {};
        rmdirIfEmpty(allocator, test_root) catch {};
    }

    const args = [_][]const u8{
        "-arch",
        "x86_64",
        "-isystem",
        shadow_dir,
        safe_joined,
        bridge_joined,
        "-iquote",
        bridge_dir,
        "-c",
        "file.c",
    };
    try appendSanitizedCompilerArgs(std.testing.io, &argv, std.testing.allocator, &args, compilerArgsTargetX86(&args), false);
    try std.testing.expect(hasString(argv.items, safe_joined));
    try std.testing.expect(hasString(argv.items, bridge_joined));
    try std.testing.expect(hasString(argv.items, bridge_dir));
    try std.testing.expect(!hasString(argv.items, shadow_dir));
}

test "compiler sanitizer keeps SIMD bridge dirs for non-x86 targets" {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(std.testing.allocator);

    const args = [_][]const u8{ "-arch", "arm64", "-isystem", "/repo/third_party/AvxToNeon", "-c", "file.c" };
    try appendSanitizedCompilerArgs(std.testing.io, &argv, std.testing.allocator, &args, compilerArgsTargetX86(&args), false);
    try std.testing.expect(hasString(argv.items, "/repo/third_party/AvxToNeon"));
}

test "arch wrapper routes x86 handoffs through standalone backend" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const script = try buildArchWrapperScript(arena.allocator(), "/tmp/rosette path/bin/rosette-arch");
    try std.testing.expect(containsIgnoreCase(script, "ROSETTE_ARCH_BACKEND"));
    try std.testing.expect(containsIgnoreCase(script, "ROSETTE_CALLER_CWD"));
    try std.testing.expect(containsIgnoreCase(script, "-x86_64"));
    try std.testing.expect(containsIgnoreCase(script, "-arch"));
    try std.testing.expect(containsIgnoreCase(script, "exec /usr/bin/arch"));
    try std.testing.expect(containsIgnoreCase(script, "ROSETTE_SCRIPT_HANDOFF_ACTIVE"));
    try std.testing.expect(containsIgnoreCase(script, "rosette-arch"));
    try std.testing.expect(containsIgnoreCase(script, "/tmp/rosette path/bin/rosette-arch"));
}

test "arch backend prefers source-built router before installed router" {
    try std.testing.expect(containsIgnoreCase(arch_backend_script, "ROSETTE_SOURCE_ROOT"));
    try std.testing.expect(containsIgnoreCase(arch_backend_script, "$HOME/.rosette/source-root"));
    try std.testing.expect(containsIgnoreCase(arch_backend_script, "ROSETTE_ROUTER_FORCE"));
    try std.testing.expect(containsIgnoreCase(arch_backend_script, "ROSETTE_ROUTE_ROOT"));
    try std.testing.expect(containsIgnoreCase(arch_backend_script, "route_root"));
    try std.testing.expect(containsIgnoreCase(arch_backend_script, "zig-out/bin/rosette-router"));
    try std.testing.expect(containsIgnoreCase(arch_backend_script, "router_source"));
    try std.testing.expect(containsIgnoreCase(arch_backend_script, "arch_backend_exec_router"));
    try std.testing.expect(containsIgnoreCase(arch_backend_script, "ROSETTE_ARCH_DRY_RUN"));
}

test "clean-state parser reads ps output lines" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const process = try parseProcessLine(
        arena.allocator(),
        " 77587     1 UE   /Users/test/.rosette/bin/rosette-shell route-arch -x86_64 /bin/bash /tmp/xenia-rosetta.ABC\n",
    );
    try std.testing.expectEqual(@as(i32, 77587), process.pid);
    try std.testing.expectEqual(@as(i32, 1), process.ppid);
    try std.testing.expectEqualStrings("UE", process.stat);
    try std.testing.expect(containsIgnoreCase(process.command, "rosette-shell route-arch"));
    try std.testing.expect(isKernelHeldStatus(process.stat));
}

test "clean-state matcher can include or exclude Xenia launches" {
    const command = "./xenia_canary.app/Contents/MacOS/xenia_canary --gpu=vulkan";
    try std.testing.expect(cleanupReason(command, .{ .include_xenia = true }) != null);
    try std.testing.expect(cleanupReason(command, .{ .include_xenia = false }) == null);
    try std.testing.expect(cleanupReason("/Users/test/.rosette/bin/rosette-router run ./xenia_canary.app/Contents/MacOS/xenia_canary", .{ .include_xenia = false }) == null);
    try std.testing.expect(cleanupReason("/Users/test/.rosette/bin/rosette-shell detect /repo", .{}) != null);
    try std.testing.expect(cleanupReason("/Users/test/.rosette/bin/rosette-shell compiler-sanitize /bin/echo", .{}) != null);
    try std.testing.expect(cleanupReason("/Users/test/.rosette/bin/rosette-compiler-sanitize /bin/echo", .{}) != null);
    try std.testing.expect(cleanupReason("/Users/test/.rosette/bin/rosette-arch -x86_64 /bin/bash /tmp/xenia-rosetta.ABC", .{}) != null);
    try std.testing.expect(cleanupReason("/Users/test/.rosette/bin/rosette-shell clean-state", .{}) == null);
    try std.testing.expect(containsIgnoreCase(compiler_launcher_script, "filtered=()"));
    try std.testing.expect(containsIgnoreCase(compiler_launcher_script, "-include"));
    try std.testing.expect(containsIgnoreCase(compiler_launcher_script, "x86_intrinsics_compat.h"));
    try std.testing.expect(containsIgnoreCase(compiler_launcher_script, "compiler_compat.h"));
    try std.testing.expect(containsIgnoreCase(compiler_launcher_script, "posix_compat.h"));
    try std.testing.expect(containsIgnoreCase(compiler_launcher_script, "cpu_feature_probe.h"));
    try std.testing.expect(containsIgnoreCase(compiler_launcher_script, "ROSETTE_MACOS_WARNING_COMPAT_ENABLE"));
    try std.testing.expect(containsIgnoreCase(compiler_launcher_script, "Wno-error=unused-variable"));
    try std.testing.expect(containsIgnoreCase(compiler_launcher_script, "Wno-error=switch"));
    try std.testing.expect(containsIgnoreCase(compiler_launcher_script, "Wno-error=shorten-64-to-32"));
    try std.testing.expect(containsIgnoreCase(x86IntrinsicsCompatH, "__cpuid("));
    try std.testing.expect(containsIgnoreCase(x86IntrinsicsCompatH, "__cpuid_count"));
    try std.testing.expect(containsIgnoreCase(x86IntrinsicsCompatH, "-Wmacro-redefined"));
    try std.testing.expect(containsIgnoreCase(compiler_launcher_script, "exec \"$compiler\""));
    try std.testing.expect(!containsIgnoreCase(compiler_launcher_script, "compiler-sanitize \"$@\""));
    try std.testing.expect(containsIgnoreCase(clean_state_backend_script, "rosette-shell route-arch"));
    try std.testing.expect(containsIgnoreCase(clean_state_backend_script, "rosette-shell compiler-sanitize"));
    try std.testing.expect(containsIgnoreCase(clean_state_backend_script, "process-quarantine.log"));
    try std.testing.expect(containsIgnoreCase(clean_state_backend_script, "pgid"));
    try std.testing.expect(containsIgnoreCase(clean_state_backend_script, "-STOP"));
    try std.testing.expect(containsIgnoreCase(clean_state_backend_script, "rosette-arch"));
    try std.testing.expect(containsIgnoreCase(clean_state_backend_script, "xenia_canary.app/contents/macos/xenia_canary"));
    try std.testing.expect(containsIgnoreCase(clean_state_backend_script, "--no-xenia"));
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
