const std = @import("std");
const exe_runner = @import("exe_runner");
const app_bundle = @import("app_bundle_parser");
const app_macho = @import("app_macho_parser");

const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("sys/stat.h");
    @cInclude("unistd.h");
});

const FAT_MAGIC: u32 = 0xCAFEBABE;
const FAT_CIGAM: u32 = 0xBEBAFECA;
const FAT_MAGIC_64: u32 = 0xCAFEBABF;
const FAT_CIGAM_64: u32 = 0xBFBAFECA;

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    if (args.len > 1 and std.mem.eql(u8, args[1], "--open")) {
        if (args.len < 3) return usage(args[0]);
        const launch_allowed = if (args.len > 3)
            !std.mem.eql(u8, args[3], "--parse-only")
        else
            true;
        try runExecutable(init, allocator, args[2], launch_allowed);
        return;
    }
    if (args.len > 1 and std.mem.eql(u8, args[1], "--open-app")) {
        if (args.len < 3) return usage(args[0]);
        const launch_allowed = if (args.len > 3)
            !std.mem.eql(u8, args[3], "--parse-only")
        else
            true;
        try runApplicationBundle(init, allocator, args[2], launch_allowed);
        return;
    }
    if (args.len > 1 and std.mem.eql(u8, args[1], "--install")) {
        const destination_dir = if (args.len >= 3) args[2] else "/Applications";
        try runInstaller(init, allocator, destination_dir);
        return;
    }
    if (args.len > 1 and std.mem.eql(u8, args[1], "--uninstall")) {
        const app_path = if (args.len >= 3) args[2] else "/Applications/Rosette.app";
        try runUninstaller(init, allocator, app_path);
        return;
    }
    if (args.len > 1 and std.mem.eql(u8, args[1], "--install-shell")) {
        const app_path = if (args.len >= 3) args[2] else try currentBundlePath(init, allocator);
        try installShellForApp(init, allocator, app_path);
        return;
    }
    if (args.len > 1 and std.mem.eql(u8, args[1], "--uninstall-shell")) {
        const app_path = if (args.len >= 3) args[2] else "/Applications/Rosette.app";
        try uninstallShellForApp(init, allocator, app_path);
        return;
    }
    if (args.len > 1 and std.mem.eql(u8, args[1], "--register")) {
        const app_path = if (args.len >= 3) args[2] else try currentBundlePath(init, allocator);
        try registerApp(init.io, app_path);
        return;
    }
    if (args.len > 1 and std.mem.eql(u8, args[1], "--unregister")) {
        const app_path = if (args.len >= 3) args[2] else "/Applications/Rosette.app";
        try unregisterApp(init.io, app_path);
        return;
    }

    usage(args[0]);
}

fn usage(exe_name: []const u8) void {
    std.debug.print(
        \\Rosette helper
        \\
        \\Usage:
        \\  {s} --open <program.exe>
        \\  {s} --open-app <program.app> [--parse-only]
        \\  {s} --install [destination-directory]
        \\  {s} --uninstall [path-to-Rosette.app]
        \\  {s} --install-shell [path-to-Rosette.app]
        \\  {s} --uninstall-shell [path-to-Rosette.app]
        \\  {s} --register [path-to-Rosette.app]
        \\  {s} --unregister [path-to-Rosette.app]
        \\
    , .{ exe_name, exe_name, exe_name, exe_name, exe_name, exe_name, exe_name, exe_name });
}

fn runExecutable(init: std.process.Init, allocator: std.mem.Allocator, exe_path: []const u8, launch_allowed: bool) !void {
    const log_path = try defaultTraceLogPath(allocator, exe_path);
    _ = std.c.write(2, "[BOOT] rosette-cli: --open ", 27);
    _ = std.c.write(2, exe_path.ptr, exe_path.len);
    _ = std.c.write(2, "\n", 1);
    std.debug.print("Rosette intake accepted: {s}\n", .{exe_path});
    std.debug.print("trace: {s}\n", .{log_path});
    try exe_runner.core.run(init, exe_path, log_path, launch_allowed);
}

fn defaultTraceLogPath(allocator: std.mem.Allocator, exe_path: []const u8) ![:0]u8 {
    const log_text = try std.fmt.allocPrint(allocator, "{s}.trace.log", .{exe_path});
    return allocator.dupeZ(u8, log_text);
}

const AppArchDiagnostic = struct {
    architecture: []const u8,
    strategy: []const u8,
    can_launch: bool,
    has_32_bit_slice: bool,
    reason: []const u8,
    suggestion: []const u8,
};

fn runApplicationBundle(init: std.process.Init, allocator: std.mem.Allocator, app_path_raw: []const u8, launch_allowed: bool) !void {
    const app_path = trimTrailingSlashes(app_path_raw);
    const log_path = try defaultAppTraceLogPath(allocator, app_path);
    std.debug.print("[BOOT] rosette-cli: --open-app {s}\n", .{app_path});
    std.debug.print("Rosette app intake accepted: {s}\n", .{app_path});
    std.debug.print("trace: {s}\n", .{log_path});

    const trace_text = try buildApplicationTrace(init, allocator, app_path, log_path, launch_allowed);
    try writeFilePath(allocator, log_path, trace_text);

    const diagnostic = try diagnoseApplicationExecutable(init, allocator, app_path);
    if (launch_allowed and diagnostic.can_launch) {
        const term = try runCmdResult(init.io, &[_][]const u8{ "/usr/bin/open", app_path });
        var launch_buf: [256]u8 = undefined;
        const launch_line = try std.fmt.bufPrint(
            &launch_buf,
            "launch_command = /usr/bin/open\nlaunch_term = {s}\n",
            .{@tagName(term)},
        );
        try appendFilePath(allocator, log_path, launch_line);
        std.debug.print("macOS app launch: {s}\n", .{@tagName(term)});
        return;
    }

    if (launch_allowed and diagnostic.has_32_bit_slice) {
        std.debug.print("macOS 32-bit app support is not implemented yet; trace captured for intake.\n", .{});
    } else if (!launch_allowed) {
        std.debug.print("macOS app launch skipped: parse-only\n", .{});
    } else {
        std.debug.print("macOS app launch skipped: {s}\n", .{diagnostic.reason});
    }
}

fn buildApplicationTrace(
    init: std.process.Init,
    allocator: std.mem.Allocator,
    app_path: []const u8,
    log_path: []const u8,
    launch_allowed: bool,
) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    const W = allocator;

    try out.appendSlice(W, "# Rosette macOS app intake trace\n");
    try appendLine(&out, W, "app", app_path);
    try appendLine(&out, W, "log", log_path);
    try appendLine(&out, W, "launch_allowed", if (launch_allowed) "true" else "false");

    var bundle = try app_bundle.detectBundle(allocator, app_path);
    defer bundle.deinit();

    try appendLine(&out, W, "bundle_name", bundle.name);
    try appendLine(&out, W, "bundle_type", @tagName(bundle.bundle_type));
    if (bundle.info_plist_path) |p| try appendLine(&out, W, "info_plist", p);
    if (bundle.resources_path) |p| try appendLine(&out, W, "resources", p);
    if (bundle.frameworks_path) |p| try appendLine(&out, W, "frameworks", p);
    if (bundle.plugins_path) |p| try appendLine(&out, W, "plugins", p);
    if (bundle.helpers_path) |p| try appendLine(&out, W, "helpers", p);

    const executable_path = try resolveBundleExecutable(init, allocator, app_path, bundle.name);
    try appendLine(&out, W, "main_executable", executable_path);

    const diagnostic = try diagnoseExecutablePath(init, allocator, executable_path);
    try appendLine(&out, W, "main_arch", diagnostic.architecture);
    try appendLine(&out, W, "launch_strategy", diagnostic.strategy);
    try appendLine(&out, W, "can_launch_now", if (diagnostic.can_launch) "true" else "false");
    try appendLine(&out, W, "diagnostic", diagnostic.reason);
    try appendLine(&out, W, "suggestion", diagnostic.suggestion);

    if (!launch_allowed) {
        try out.appendSlice(W, "launch = skipped reason=parse_only\n");
    } else if (diagnostic.has_32_bit_slice and !diagnostic.can_launch) {
        try out.appendSlice(W, "translation = macos32_pending\n");
        try out.appendSlice(W, "launch = skipped reason=macos32_translation_pending\n");
    } else if (diagnostic.can_launch) {
        try out.appendSlice(W, "launch = pending command=/usr/bin/open\n");
    } else {
        try out.appendSlice(W, "launch = skipped reason=unsupported_architecture\n");
    }

    return out.toOwnedSlice(W);
}

fn defaultAppTraceLogPath(allocator: std.mem.Allocator, app_path_raw: []const u8) ![:0]u8 {
    const app_path = trimTrailingSlashes(app_path_raw);
    const home_ptr = std.c.getenv("HOME") orelse return error.HomeNotSet;
    const home = std.mem.sliceTo(home_ptr, 0);
    const trace_dir = try std.fs.path.join(allocator, &.{ home, "Library", "Application Support", "Rosette", "Traces" });
    try makePathRecursive(allocator, trace_dir);

    const app_name = std.fs.path.basename(app_path);
    const trace_name = if (app_name.len > 0) app_name else "Application.app";
    const log_path = try std.fs.path.join(allocator, &.{ trace_dir, try std.fmt.allocPrint(allocator, "{s}.trace.log", .{trace_name}) });
    return allocator.dupeZ(u8, log_path);
}

fn trimTrailingSlashes(path: []const u8) []const u8 {
    var end = path.len;
    while (end > 1 and path[end - 1] == '/') end -= 1;
    return path[0..end];
}

fn appendLine(out: *std.ArrayList(u8), allocator: std.mem.Allocator, key: []const u8, value: []const u8) !void {
    const line = try std.fmt.allocPrint(allocator, "{s} = {s}\n", .{ key, value });
    try out.appendSlice(allocator, line);
}

fn resolveBundleExecutable(
    init: std.process.Init,
    allocator: std.mem.Allocator,
    app_path: []const u8,
    bundle_name: []const u8,
) ![]const u8 {
    const plist_path = try std.fs.path.join(allocator, &.{ app_path, "Contents", "Info.plist" });
    if (readCFBundleExecutable(init, allocator, plist_path)) |exe_name| {
        return std.fs.path.join(allocator, &.{ app_path, "Contents", "MacOS", exe_name });
    } else |_| {}

    const fallback_name = if (std.mem.endsWith(u8, bundle_name, ".app"))
        bundle_name[0 .. bundle_name.len - 4]
    else
        bundle_name;
    return std.fs.path.join(allocator, &.{ app_path, "Contents", "MacOS", fallback_name });
}

fn readCFBundleExecutable(
    init: std.process.Init,
    allocator: std.mem.Allocator,
    plist_path: []const u8,
) ![]const u8 {
    const data = try std.Io.Dir.cwd().readFileAlloc(init.io, plist_path, allocator, .limited(1024 * 1024));
    const key = "<key>CFBundleExecutable</key>";
    const key_pos = std.mem.indexOf(u8, data, key) orelse return error.BundleExecutableMissing;
    const tail = data[key_pos + key.len ..];
    const open_tag = "<string>";
    const close_tag = "</string>";
    const open_pos = std.mem.indexOf(u8, tail, open_tag) orelse return error.BundleExecutableMissing;
    const value_start = open_pos + open_tag.len;
    const value_tail = tail[value_start..];
    const close_pos = std.mem.indexOf(u8, value_tail, close_tag) orelse return error.BundleExecutableMissing;
    return allocator.dupe(u8, std.mem.trim(u8, value_tail[0..close_pos], " \t\r\n"));
}

fn diagnoseApplicationExecutable(init: std.process.Init, allocator: std.mem.Allocator, app_path: []const u8) !AppArchDiagnostic {
    var bundle = try app_bundle.detectBundle(allocator, app_path);
    defer bundle.deinit();
    const executable_path = try resolveBundleExecutable(init, allocator, app_path, bundle.name);
    return diagnoseExecutablePath(init, allocator, executable_path);
}

fn diagnoseExecutablePath(init: std.process.Init, allocator: std.mem.Allocator, executable_path: []const u8) !AppArchDiagnostic {
    const data = std.Io.Dir.cwd().readFileAlloc(init.io, executable_path, allocator, .limited(1024 * 1024)) catch |err| {
        return AppArchDiagnostic{
            .architecture = "missing",
            .strategy = "unsupported",
            .can_launch = false,
            .has_32_bit_slice = false,
            .reason = try std.fmt.allocPrint(allocator, "cannot open executable: {s}", .{@errorName(err)}),
            .suggestion = "verify the app bundle is intact",
        };
    };

    if (data.len < 8) {
        return AppArchDiagnostic{
            .architecture = "truncated",
            .strategy = "unsupported",
            .can_launch = false,
            .has_32_bit_slice = false,
            .reason = "executable is too small to contain a Mach-O header",
            .suggestion = "verify the app binary",
        };
    }

    const fat_magic = std.mem.readInt(u32, data[0..4], .big);
    if (fat_magic == FAT_MAGIC or fat_magic == FAT_MAGIC_64 or
        fat_magic == FAT_CIGAM or fat_magic == FAT_CIGAM_64)
    {
        return diagnoseFatHeader(allocator, data, fat_magic);
    }

    const thin_magic = std.mem.readInt(u32, data[0..4], .little);
    if (thin_magic == app_macho.MH_MAGIC or thin_magic == app_macho.MH_MAGIC_64) {
        return diagnoseThinMachO(std.mem.readInt(u32, data[4..8], .little));
    }
    if (thin_magic == app_macho.MH_CIGAM or thin_magic == app_macho.MH_CIGAM_64) {
        return diagnoseThinMachO(std.mem.readInt(u32, data[4..8], .big));
    }

    return AppArchDiagnostic{
        .architecture = "unknown",
        .strategy = "unsupported",
        .can_launch = false,
        .has_32_bit_slice = false,
        .reason = "unrecognised Mach-O magic",
        .suggestion = "verify the file is a Mach-O executable",
    };
}

fn diagnoseThinMachO(cputype: u32) AppArchDiagnostic {
    if (cputype == app_macho.CPU_TYPE_ARM64) {
        return .{
            .architecture = "arm64",
            .strategy = "direct_native",
            .can_launch = true,
            .has_32_bit_slice = false,
            .reason = "native ARM64 Mach-O",
            .suggestion = "launch directly",
        };
    }
    if (cputype == app_macho.CPU_TYPE_X86_64) {
        return .{
            .architecture = "x86_64",
            .strategy = "rosetta2_native",
            .can_launch = true,
            .has_32_bit_slice = false,
            .reason = "64-bit Intel Mach-O can launch through macOS Rosetta 2",
            .suggestion = "launch with /usr/bin/open",
        };
    }
    if (cputype == app_macho.CPU_TYPE_I386) {
        return .{
            .architecture = "i386",
            .strategy = "macos32_translation_pending",
            .can_launch = false,
            .has_32_bit_slice = true,
            .reason = "32-bit Intel macOS apps need Rosette's future macOS 32-bit translation path",
            .suggestion = "trace intake now; implement 32-bit Cocoa/Carbon thunking later",
        };
    }
    return .{
        .architecture = "unknown",
        .strategy = "unsupported",
        .can_launch = false,
        .has_32_bit_slice = false,
        .reason = "unsupported Mach-O CPU type",
        .suggestion = "verify the binary architecture",
    };
}

fn diagnoseFatHeader(allocator: std.mem.Allocator, data: []const u8, magic: u32) !AppArchDiagnostic {
    const is_64 = magic == FAT_MAGIC_64 or magic == FAT_CIGAM_64;
    const endian: std.builtin.Endian = if (magic == FAT_MAGIC or magic == FAT_MAGIC_64) .big else .little;
    const arch_count = std.mem.readInt(u32, data[4..8], endian);
    const arch_size: usize = if (is_64) 32 else 20;
    var pos: usize = 8;
    var has_arm64 = false;
    var has_x86_64 = false;
    var has_i386 = false;
    var seen: usize = 0;

    while (seen < arch_count and pos + arch_size <= data.len) : ({
        seen += 1;
        pos += arch_size;
    }) {
        const cputype = std.mem.readInt(u32, data[pos..][0..4], endian);
        has_arm64 = has_arm64 or cputype == app_macho.CPU_TYPE_ARM64;
        has_x86_64 = has_x86_64 or cputype == app_macho.CPU_TYPE_X86_64;
        has_i386 = has_i386 or cputype == app_macho.CPU_TYPE_I386;
    }

    const arch_text = try std.fmt.allocPrint(
        allocator,
        "universal({s}{s}{s})",
        .{
            if (has_arm64) "arm64" else "",
            if (has_x86_64) if (has_arm64) ",x86_64" else "x86_64" else "",
            if (has_i386) if (has_arm64 or has_x86_64) ",i386" else "i386" else "",
        },
    );

    if (has_arm64) {
        return .{
            .architecture = arch_text,
            .strategy = "direct_native",
            .can_launch = true,
            .has_32_bit_slice = has_i386,
            .reason = "universal app includes an ARM64 slice",
            .suggestion = "launch directly",
        };
    }
    if (has_x86_64) {
        return .{
            .architecture = arch_text,
            .strategy = "rosetta2_native",
            .can_launch = true,
            .has_32_bit_slice = has_i386,
            .reason = "universal app includes an x86_64 slice for macOS Rosetta 2",
            .suggestion = "launch with /usr/bin/open",
        };
    }
    if (has_i386) {
        return .{
            .architecture = arch_text,
            .strategy = "macos32_translation_pending",
            .can_launch = false,
            .has_32_bit_slice = true,
            .reason = "universal app only exposes a 32-bit Intel launchable slice",
            .suggestion = "trace intake now; implement 32-bit macOS translation later",
        };
    }

    return .{
        .architecture = arch_text,
        .strategy = "unsupported",
        .can_launch = false,
        .has_32_bit_slice = false,
        .reason = "universal app has no ARM64, x86_64, or i386 slice",
        .suggestion = "verify the app architecture",
    };
}

fn makePathRecursive(allocator: std.mem.Allocator, raw_path: []const u8) !void {
    if (raw_path.len == 0) return;

    var current: std.ArrayList(u8) = .empty;
    defer current.deinit(allocator);

    if (raw_path[0] == '/') {
        try current.append(allocator, '/');
    }

    var parts = std.mem.splitScalar(u8, raw_path, '/');
    while (parts.next()) |part| {
        if (part.len == 0) continue;
        if (current.items.len > 0 and current.items[current.items.len - 1] != '/') {
            try current.append(allocator, '/');
        }
        try current.appendSlice(allocator, part);
        const path_z = try allocator.dupeZ(u8, current.items);
        if (c.mkdir(path_z.ptr, 0o755) != 0) {
            if (c.access(path_z.ptr, 0) != 0) return error.FileNotFound;
        }
    }
}

fn writeFilePath(allocator: std.mem.Allocator, path: []const u8, data: []const u8) !void {
    const path_z = try allocator.dupeZ(u8, path);
    const fp = c.fopen(path_z.ptr, "wb");
    if (fp == null) return error.FileNotFound;
    defer _ = c.fclose(fp);

    if (data.len != 0) {
        const wrote = c.fwrite(data.ptr, 1, data.len, fp);
        if (wrote != data.len) return error.FileNotFound;
    }
}

fn appendFilePath(allocator: std.mem.Allocator, path: []const u8, data: []const u8) !void {
    const path_z = try allocator.dupeZ(u8, path);
    const fp = c.fopen(path_z.ptr, "ab");
    if (fp == null) return error.FileNotFound;
    defer _ = c.fclose(fp);

    if (data.len != 0) {
        const wrote = c.fwrite(data.ptr, 1, data.len, fp);
        if (wrote != data.len) return error.FileNotFound;
    }
}

fn runInstaller(init: std.process.Init, allocator: std.mem.Allocator, destination_dir: []const u8) !void {
    const bundle_path = try currentBundlePath(init, allocator);
    const installed_path = try std.fs.path.join(allocator, &.{ destination_dir, "Rosette.app" });

    std.debug.print("Installing Rosette...\n", .{});
    std.debug.print("source: {s}\n", .{bundle_path});
    std.debug.print("target: {s}\n", .{installed_path});

    try runCmd(init.io, &[_][]const u8{ "rm", "-rf", installed_path });
    try runCmd(init.io, &[_][]const u8{ "cp", "-R", bundle_path, destination_dir });
    registerApp(init.io, installed_path) catch |err| {
        std.debug.print("Finder registration skipped: {s}\n", .{@errorName(err)});
    };
    try installShellForApp(init, allocator, installed_path);

    std.debug.print("Rosette installed successfully.\n", .{});
}

fn runUninstaller(init: std.process.Init, allocator: std.mem.Allocator, app_path: []const u8) !void {
    std.debug.print("Removing Rosette from {s}\n", .{app_path});
    uninstallShellForApp(init, allocator, app_path) catch |err| {
        std.debug.print("Rosette shell uninstall skipped: {s}\n", .{@errorName(err)});
    };
    try unregisterApp(init.io, app_path);
    try runCmd(init.io, &[_][]const u8{ "rm", "-rf", app_path });
    try removeLaunchAgent(init.io);
    std.debug.print("Rosette uninstalled successfully.\n", .{});
}

fn installShellForApp(init: std.process.Init, allocator: std.mem.Allocator, app_path: []const u8) !void {
    const helper = try shellHelperPath(allocator, app_path);
    if (!pathExists(allocator, helper)) {
        std.debug.print("Rosette shell helper not found: {s}\n", .{helper});
        return;
    }
    const runtime_root = try std.fs.path.join(allocator, &.{ app_path, "Contents", "Resources", "rosette-runtime" });
    std.debug.print("Installing Rosette global shell integration...\n", .{});
    std.debug.print("  command: rosette\n", .{});
    std.debug.print("  helpers: rosette-shell, elf_processor, macho_processor, rosette-router, rosette_assembler_runner\n", .{});
    std.debug.print("  direct launch: ./program for detected x86-64 ELF assignments\n", .{});
    std.debug.print("  compatibility route: rosette route run --prefer-intel /path/to/App.app\n", .{});
    std.debug.print("  config: ~/.rosette/config.toml with dump_results=\"auto\"\n", .{});
    try runCmd(init.io, &[_][]const u8{ helper, "install", runtime_root });
}

fn uninstallShellForApp(init: std.process.Init, allocator: std.mem.Allocator, app_path: []const u8) !void {
    const helper = try shellHelperPath(allocator, app_path);
    if (pathExists(allocator, helper)) {
        std.debug.print("Removing Rosette global shell integration...\n", .{});
        try runCmd(init.io, &[_][]const u8{ helper, "uninstall" });
        return;
    }

    const home = std.c.getenv("HOME") orelse return;
    const fallback = try std.fs.path.join(allocator, &.{ std.mem.sliceTo(home, 0), ".rosette", "bin", "rosette-shell" });
    if (pathExists(allocator, fallback)) {
        std.debug.print("Removing Rosette global shell integration via installed helper...\n", .{});
        try runCmd(init.io, &[_][]const u8{ fallback, "uninstall" });
    }
}

fn shellHelperPath(allocator: std.mem.Allocator, app_path: []const u8) ![]const u8 {
    return try std.fs.path.join(allocator, &.{ app_path, "Contents", "MacOS", "rosette-shell" });
}

fn currentBundlePath(init: std.process.Init, allocator: std.mem.Allocator) ![]const u8 {
    const self_path = try std.process.executablePathAlloc(init.io, allocator);
    const suffix = "Contents/MacOS/rosette-cli";
    if (std.mem.endsWith(u8, self_path, suffix)) {
        const end = self_path.len - suffix.len;
        return self_path[0..end];
    }
    return "/Applications/Rosette.app";
}

fn registerApp(io: std.Io, app_path: []const u8) !void {
    try runCmd(io, &[_][]const u8{
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
        "-f",
        app_path,
    });
}

fn unregisterApp(io: std.Io, app_path: []const u8) !void {
    try runCmd(io, &[_][]const u8{
        "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister",
        "-u",
        app_path,
    });
}

fn pathExists(allocator: std.mem.Allocator, path: []const u8) bool {
    const path_z = allocator.dupeZ(u8, path) catch return false;
    return c.access(path_z.ptr, 0) == 0;
}

fn removeLaunchAgent(io: std.Io) !void {
    const home = std.c.getenv("HOME") orelse return;
    var buf: [512]u8 = undefined;
    const agent_path = try std.fmt.bufPrint(&buf, "{s}/Library/LaunchAgents/com.rosette.translator.plist", .{home});
    try runCmd(io, &[_][]const u8{ "rm", "-f", agent_path });
}

fn runCmd(io: std.Io, argv: []const []const u8) !void {
    _ = try runCmdResult(io, argv);
}

fn runCmdResult(io: std.Io, argv: []const []const u8) !std.process.Child.Term {
    var child = try std.process.spawn(io, .{
        .argv = argv,
        .stdout = .inherit,
        .stderr = .inherit,
    });
    const term = try child.wait(io);
    return term;
}

test "default trace path follows executable path" {
    const log_path = try defaultTraceLogPath(std.testing.allocator, "assets/exe_examples/Console-Tetris.exe");
    defer std.testing.allocator.free(log_path);
    try std.testing.expectEqualStrings("assets/exe_examples/Console-Tetris.exe.trace.log", log_path);
}
