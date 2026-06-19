const std = @import("std");
const fmt = @import("pe_format.zig");
const parser = @import("pe_parser.zig");
const pkg = @import("rosette_package.zig");
const trace = @import("mandatory_trace.zig");
const x86_disasm = @import("../disasm_logger/x86_disasm.zig");
const process_guard = @import("entrypoint_kernel_process_guard");
const raw_decode = @import("../../x86-ASM/raw_decoder.zig");
const runtime_abi = @import("runtime_abi_handshake");
const traps = runtime_abi.traps;
const code_text = @import("entrypoint_code_text_segment");
const imports_mod = @import("imports/imports.zig");
const clr_runtime = @import("../../../include/runtime/clr_runtime.zig");

const image_scn_mem_execute: u32 = 0x2000_0000;

extern fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;
extern fn system(command: [*:0]const u8) c_int;

fn machineName(machine: u16) []const u8 {
    return switch (machine) {
        fmt.coff.machine_i386 => "i386",
        fmt.coff.machine_amd64 => "amd64",
        else => "unknown",
    };
}

fn subsystemName(subsystem: u16) []const u8 {
    return switch (subsystem) {
        fmt.coff.subsystem_windows_gui => "windows_gui",
        fmt.coff.subsystem_windows_cui => "windows_cui",
        else => "unknown",
    };
}

fn hasMscoreeEntry(import_dir: *const imports_mod.ImportDirectory) bool {
    for (import_dir.descriptors) |desc| {
        if (std.ascii.eqlIgnoreCase(desc.dll_name, "mscoree.dll") and
            std.mem.eql(u8, desc.function_name, "_CorExeMain"))
        {
            return true;
        }
    }
    return false;
}

fn setEnvValue(allocator: std.mem.Allocator, name: [*:0]const u8, value: []const u8) !void {
    const value_z = try allocator.dupeZ(u8, value);
    if (setenv(name, value_z.ptr, 1) != 0) return error.SetEnvironmentFailed;
}

fn setEnvLiteral(name: [*:0]const u8, value: [*:0]const u8) !void {
    if (setenv(name, value, 1) != 0) return error.SetEnvironmentFailed;
}

fn prepareNativeMscoreeEnvironment(
    allocator: std.mem.Allocator,
    exe_path: []const u8,
    log_path: [:0]const u8,
    managed_gui: bool,
) !void {
    try setEnvLiteral("ROSETTE_ENABLE_NATIVE_MSCOREE", "1");
    try setEnvLiteral("ROSETTE_MANAGED_GUI", if (managed_gui) "1" else "0");
    try setEnvValue(allocator, "ROSETTE_EXE_PATH", exe_path);
    try setEnvValue(allocator, "ROSETTE_TRACE_PATH", log_path);
}

fn resolveMscoreeWindowHelperApp(init: std.process.Init, allocator: std.mem.Allocator) ![]const u8 {
    if (std.c.getenv("ROSETTE_MSCOREE_WINDOW_HELPER")) |env_ptr| {
        const env_path = std.mem.sliceTo(env_ptr, 0);
        if (env_path.len > 0) return allocator.dupe(u8, env_path);
    }

    const repo_helper_app = "zig-out/bin/RosetteMscoreeWindow.app";
    std.Io.Dir.cwd().access(init.io, repo_helper_app, .{}) catch |repo_err| {
        const self_path = std.process.executablePathAlloc(init.io, allocator) catch return repo_err;
        const self_dir = std.fs.path.dirname(self_path) orelse ".";
        const sibling = try std.fs.path.join(allocator, &.{ self_dir, "RosetteMscoreeWindow.app" });
        std.Io.Dir.cwd().access(init.io, sibling, .{}) catch return repo_err;
        return sibling;
    };
    return std.fs.path.resolve(allocator, &.{repo_helper_app});
}

fn quoteShellPath(out: []u8, path: []const u8) ?[]const u8 {
    var index: usize = 0;
    if (index >= out.len) return null;
    out[index] = '\'';
    index += 1;

    for (path) |ch| {
        if (ch == '\'') {
            const escaped = "'\\''";
            if (index + escaped.len > out.len) return null;
            std.mem.copyForwards(u8, out[index..], escaped);
            index += escaped.len;
        } else {
            if (index + 1 > out.len) return null;
            out[index] = ch;
            index += 1;
        }
    }

    if (index + 1 > out.len) return null;
    out[index] = '\'';
    index += 1;
    return out[0..index];
}

fn launchManagedWindowHelper(init: std.process.Init, allocator: std.mem.Allocator, exe_path: []const u8, log_path: []const u8) !void {
    const helper_app_path = try resolveMscoreeWindowHelperApp(init, allocator);
    try setEnvValue(allocator, "ROSETTE_MSCOREE_WINDOW_HELPER", helper_app_path);

    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = if (std.c.getcwd(&cwd_buf, cwd_buf.len)) |cwd_ptr|
        std.mem.sliceTo(cwd_ptr, 0)
    else
        ".";
    const helper_exe_path = if (std.fs.path.isAbsolute(exe_path))
        exe_path
    else
        try std.fs.path.resolve(allocator, &.{ cwd, exe_path });
    const helper_log_path = if (std.fs.path.isAbsolute(log_path))
        log_path
    else
        try std.fs.path.resolve(allocator, &.{ cwd, log_path });

    var helper_quoted_buf: [std.fs.max_path_bytes + 16]u8 = undefined;
    const helper_quoted = quoteShellPath(&helper_quoted_buf, helper_app_path) orelse return error.NoSpaceLeft;

    var exe_quoted_buf: [std.fs.max_path_bytes + 16]u8 = undefined;
    const exe_quoted = quoteShellPath(&exe_quoted_buf, helper_exe_path) orelse return error.NoSpaceLeft;

    var log_quoted_buf: [std.fs.max_path_bytes + 16]u8 = undefined;
    const log_quoted = quoteShellPath(&log_quoted_buf, helper_log_path) orelse return error.NoSpaceLeft;

    const autoclose_value = if (std.c.getenv("ROSETTE_MANAGED_WINDOW_AUTOCLOSE_MS")) |autoclose_ptr|
        std.mem.sliceTo(autoclose_ptr, 0)
    else
        "";
    var autoclose_quoted_buf: [64]u8 = undefined;
    const autoclose_quoted = quoteShellPath(&autoclose_quoted_buf, autoclose_value) orelse return error.NoSpaceLeft;

    var command_buf: [std.fs.max_path_bytes * 4 + 256]u8 = undefined;
    const command = try std.fmt.bufPrintZ(
        &command_buf,
        "/usr/bin/open -n {s} --args {s} {s} {s}",
        .{ helper_quoted, exe_quoted, log_quoted, autoclose_quoted },
    );
    if (system(command.ptr) != 0) return error.ManagedWindowHelperLaunchFailed;
}

fn writeFileUri(buffer: []u8, path: []const u8) ![]const u8 {
    var index: usize = 0;
    if (buffer.len < 7) return error.NoSpaceLeft;
    std.mem.copyForwards(u8, buffer[index..], "file://");
    index += 7;

    for (path) |ch| {
        if (ch == ' ') {
            if (index + 3 > buffer.len) return error.NoSpaceLeft;
            std.mem.copyForwards(u8, buffer[index..], "%20");
            index += 3;
        } else {
            if (index + 1 > buffer.len) return error.NoSpaceLeft;
            buffer[index] = ch;
            index += 1;
        }
    }

    return buffer[0..index];
}

fn appendHex(buffer: []u8, bytes: []const u8) []const u8 {
    var hex_len: usize = 0;
    for (bytes, 0..) |b, i| {
        if (i > 0) {
            buffer[hex_len] = ' ';
            hex_len += 1;
        }
        _ = std.fmt.bufPrint(buffer[hex_len..], "{X:0>2}", .{b}) catch break;
        hex_len += 2;
    }
    return buffer[0..hex_len];
}

fn sectionName(section: *const parser.Section) []const u8 {
    const raw_name = std.mem.sliceTo(&section.name, 0);
    return if (raw_name.len == 0) "<unnamed>" else raw_name;
}

fn installCodeTextSegments(exec: anytype, image: *const parser.Image) void {
    const image_base_u32: u32 = @as(u32, @truncate(image.image_base));
    exec.setLoadedImageSize(image.size_of_image);
    exec.clearCodeTextSegments();
    for (image.sections) |section| {
        const section_size = if (section.virtual_size != 0) section.virtual_size else section.raw_size;
        if (section_size == 0) continue;
        exec.addCodeTextSegment(code_text.Segment.init(
            image_base_u32 +% section.virtual_address,
            section_size,
            (section.characteristics & image_scn_mem_execute) != 0,
            sectionName(&section),
        ));
    }
}

fn logInstructionPointerTrap(exec: anytype, guard: code_text.Guard, check: code_text.CheckResult) void {
    if (check.isValid()) return;
    const eip = exec.regs.eip;
    if (code_text.rvaToVaIfInImage(guard, eip)) |va| {
        var line_buf: [640]u8 = undefined;
        const line = std.fmt.bufPrint(
            &line_buf,
            "abort_trap = {s} reason={s} description=\"{s}\" eip=0x{X:0>8} image=[0x{X:0>8}..0x{X:0>8}] pending_exception=0x{X} rva_hint_va=0x{X:0>8}\n",
            .{ @tagName(traps.AbortTrap.BadInstructionPointer), @tagName(check.status), traps.description(.BadInstructionPointer), eip, guard.image_base, guard.imageEnd(), exec.regs.pending_exception, va },
        ) catch return;
        trace.logText(line);
        std.debug.print("  {s}", .{line});
        return;
    }

    var line_buf: [576]u8 = undefined;
    const line = std.fmt.bufPrint(
        &line_buf,
        "abort_trap = {s} reason={s} description=\"{s}\" eip=0x{X:0>8} image=[0x{X:0>8}..0x{X:0>8}] pending_exception=0x{X}\n",
        .{ @tagName(traps.AbortTrap.BadInstructionPointer), @tagName(check.status), traps.description(.BadInstructionPointer), eip, guard.image_base, guard.imageEnd(), exec.regs.pending_exception },
    ) catch return;
    trace.logText(line);
    std.debug.print("  {s}", .{line});
}

fn logUnsupportedInstructionTrap(exec: anytype, decoded: raw_decode.DecodedInstruction) void {
    var line_buf: [640]u8 = undefined;
    const line = std.fmt.bufPrint(
        &line_buf,
        "abort_trap = {s} reason={s} description=\"{s}\" eip=0x{X:0>8} isa={s} pending_exception=0x{X} detail=\"{s}\"\n",
        .{ @tagName(traps.AbortTrap.UnsupportedInstruction), @tagName(decoded.status), traps.description(.UnsupportedInstruction), exec.regs.eip, decoded.isa_path, exec.regs.pending_exception, decoded.unsupported_reason },
    ) catch return;
    trace.logText(line);
    std.debug.print("  {s}", .{line});
}

fn logHaltContext(exec: anytype) void {
    const guard = exec.codeTextGuard();
    const base = guard.image_base;
    const image_end = guard.imageEnd();
    const eip = exec.regs.eip;
    const ip_check = code_text.checkInstructionPointer(guard, eip, 1);
    logInstructionPointerTrap(exec, guard, ip_check);

    if (eip < base) {
        var line_buf: [320]u8 = undefined;
        const line = std.fmt.bufPrint(
            &line_buf,
            "halt_context = outside_image eip=0x{X:0>8} image=[0x{X:0>8}..0x{X:0>8}] pending_exception=0x{X}\n",
            .{ eip, base, image_end, exec.regs.pending_exception },
        ) catch return;
        trace.logText(line);
        std.debug.print("  {s}", .{line});
        return;
    }

    const off = eip - base;
    if (@as(u64, eip) >= image_end or off >= exec.mem.data.len) {
        var line_buf: [320]u8 = undefined;
        const line = std.fmt.bufPrint(
            &line_buf,
            "halt_context = outside_image eip=0x{X:0>8} image=[0x{X:0>8}..0x{X:0>8}] pending_exception=0x{X}\n",
            .{ eip, base, image_end, exec.regs.pending_exception },
        ) catch return;
        trace.logText(line);
        std.debug.print("  {s}", .{line});
        return;
    }

    const window_len = @min(@as(usize, raw_decode.max_instruction_len), exec.mem.data.len - off);
    const raw_window = exec.mem.data[off .. off + window_len];
    var hex_buf: [128]u8 = undefined;
    const decoded = raw_decode.decodeInstruction(eip, raw_window) catch {
        const raw = raw_window[0..@min(@as(usize, 12), raw_window.len)];
        const hex = appendHex(&hex_buf, raw);
        var trap_buf: [512]u8 = undefined;
        const trap_line = std.fmt.bufPrint(
            &trap_buf,
            "abort_trap = {s} reason=undecodable description=\"{s}\" eip=0x{X:0>8} pending_exception=0x{X}\n",
            .{ @tagName(traps.AbortTrap.UnsupportedInstruction), traps.description(.UnsupportedInstruction), eip, exec.regs.pending_exception },
        ) catch return;
        trace.logText(trap_line);
        std.debug.print("  {s}", .{trap_line});
        var line_buf: [384]u8 = undefined;
        const line = std.fmt.bufPrint(
            &line_buf,
            "halt_context = undecodable eip=0x{X:0>8} bytes=[{s}] pending_exception=0x{X}\n",
            .{ eip, hex, exec.regs.pending_exception },
        ) catch return;
        trace.logText(line);
        std.debug.print("  {s}", .{line});
        return;
    };
    if (decoded.status != .executable) logUnsupportedInstructionTrap(exec, decoded);
    const raw = decoded.bytes[0..decoded.len];
    const hex = appendHex(&hex_buf, raw);
    var line_buf: [512]u8 = undefined;
    const line = std.fmt.bufPrint(
        &line_buf,
        "halt_context = decoded eip=0x{X:0>8} instruction=\"{s}\" bytes=[{s}] isa={s} status={s} pending_exception=0x{X} reason=\"{s}\"\n",
        .{ eip, decoded.textSlice(), hex, decoded.isa_path, @tagName(decoded.status), exec.regs.pending_exception, decoded.unsupported_reason },
    ) catch return;
    trace.logText(line);
    std.debug.print("  {s}", .{line});
}

fn logRawStep(exec: anytype) void {
    const base = exec.mem.base;
    const eip = exec.regs.eip;
    if (eip < base) return;
    const off = eip - base;
    if (off >= exec.mem.data.len) return;

    const window_len = @min(@as(usize, raw_decode.max_instruction_len), exec.mem.data.len - off);
    const raw_window = exec.mem.data[off .. off + window_len];
    const decoded = raw_decode.decodeInstruction(eip, raw_window) catch return;
    var hex_buf: [128]u8 = undefined;
    const hex = appendHex(&hex_buf, decoded.bytes[0..decoded.len]);
    var line_buf: [640]u8 = undefined;
    const line = std.fmt.bufPrint(
        &line_buf,
        "0x{X:0>8}: {s} [{s}] ; isa={s} status={s} eax=0x{X:0>8} ebx=0x{X:0>8} ecx=0x{X:0>8} edx=0x{X:0>8} esp=0x{X:0>8}\n",
        .{
            eip,
            decoded.textSlice(),
            hex,
            decoded.isa_path,
            @tagName(decoded.status),
            exec.regs.eax,
            exec.regs.ebx,
            exec.regs.ecx,
            exec.regs.edx,
            exec.regs.esp,
        },
    ) catch return;
    trace.logText(line);
}

fn bootLog(stage: []const u8) void {
    _ = std.c.write(2, "[BOOT] ", 7);
    _ = std.c.write(2, stage.ptr, stage.len);
    _ = std.c.write(2, "\n", 1);
}

pub fn run(init: std.process.Init, exe_path: []const u8, log_path: [:0]const u8, launch_allowed: bool) !void {
    bootLog("0_enter_run: launch exe_runner_core");
    bootLog("  exe_path: starting PE intake");

    var exe_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const exe_announce = std.fmt.bufPrint(
        &exe_path_buf,
        "  file: {s}\n  log:  {s}\n  launch_allowed: {}",
        .{ exe_path, log_path, launch_allowed },
    ) catch "";
    if (exe_announce.len > 0) {
        _ = std.c.write(2, exe_announce.ptr, exe_announce.len);
        _ = std.c.write(2, "\n", 1);
    }

    const allocator = init.arena.allocator();

    bootLog("1_read_exe: reading file into memory");
    const exe_bytes = try std.Io.Dir.cwd().readFileAlloc(init.io, exe_path, allocator, .limited(128 * 1024 * 1024));

    bootLog("2_enable_trace");
    trace.enable(log_path.ptr);
    defer trace.disable();

    var intro_buf: [512]u8 = undefined;
    const intro = try std.fmt.bufPrint(
        &intro_buf,
        "# PE intake session\nfile = {s}\nlog = {s}\n",
        .{ exe_path, log_path },
    );
    trace.logText(intro);

    bootLog("3_parse_pe");
    const image = try parser.parse(allocator, exe_bytes);
    defer allocator.free(image.sections);

    bootLog("4_pe_summary: logging PE metadata");
    var summary_buf: [640]u8 = undefined;
    const summary = try std.fmt.bufPrint(
        &summary_buf,
        "machine = {s} (0x{X:0>4})\nentry_rva = 0x{X:0>8}\nimage_base = 0x{X}\nsubsystem = {s} (0x{X:0>4})\nsection_alignment = 0x{X:0>8}\nfile_alignment = 0x{X:0>8}\nsize_of_image = 0x{X:0>8}\nsize_of_headers = 0x{X:0>8}\nsections = {d}\n",
        .{
            machineName(image.machine),
            image.machine,
            image.entry_rva,
            image.image_base,
            subsystemName(image.subsystem),
            image.subsystem,
            image.section_alignment,
            image.file_alignment,
            image.size_of_image,
            image.size_of_headers,
            image.number_of_sections,
        },
    );
    trace.logText(summary);

    bootLog("5_sections");
    for (image.sections, 0..) |section, index| {
        const section_name = sectionName(&section);
        var section_buf: [256]u8 = undefined;
        const section_line = try std.fmt.bufPrint(
            &section_buf,
            "section[{d}] name={s} va=0x{X:0>8} vsz=0x{X:0>8} raw=0x{X:0>8} raw_off=0x{X:0>8} chars=0x{X:0>8}\n",
            .{
                index,
                section_name,
                section.virtual_address,
                section.virtual_size,
                section.raw_size,
                section.raw_offset,
                section.characteristics,
            },
        );
        trace.logText(section_line);
    }

    bootLog("6_check_package");
    if (pkg.findSection(&image, pkg.PackageSectionName)) |section| {
        const metadata = try pkg.parseMetadata(pkg.rawSectionBytes(exe_bytes, section));
        var launch_buf: [1024]u8 = undefined;
        const launch_note = try std.fmt.bufPrint(
            &launch_buf,
            "rosette_package = true\nsuite = {s}\nlaunch = {s}\ncwd = {s}\ninteractive = {s}\n",
            .{
                metadata.suite,
                metadata.launch,
                metadata.cwd,
                if (metadata.interactive) "true" else "false",
            },
        );
        trace.logText(launch_note);

        std.debug.print(
            "  package: Rosette app wrapper\n  launch: {s}\n  cwd: {s}\n",
            .{ metadata.launch, metadata.cwd },
        );

        if (!launch_allowed) {
            trace.logText("launch_skipped = parse_only\n");
            return;
        }

        bootLog("6a_launch_host: spawning native .host binary");
        var base_cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
        const base_cwd = if (std.c.getcwd(&base_cwd_buf, base_cwd_buf.len)) |ptr|
            std.mem.sliceTo(ptr, 0)
        else
            ".";

        const abs_exe_path = try std.fs.path.resolve(allocator, &.{ base_cwd, exe_path });
        const abs_log_path = if (std.fs.path.isAbsolute(log_path))
            try allocator.dupe(u8, log_path)
        else
            try std.fs.path.resolve(allocator, &.{ base_cwd, log_path });
        const exe_dir = std.fs.path.dirname(abs_exe_path) orelse "/";
        const resolved_launch = try std.fs.path.resolve(allocator, &.{ exe_dir, metadata.launch });
        const resolved_cwd = try std.fs.path.resolve(allocator, &.{ exe_dir, metadata.cwd });

        const final_launch = blk: {
            std.Io.Dir.cwd().access(init.io, resolved_launch, .{}) catch {
                const fallback = try std.fmt.allocPrint(allocator, "{s}.host", .{metadata.suite});
                const fallback_path = try std.fs.path.resolve(allocator, &.{ exe_dir, fallback });
                std.Io.Dir.cwd().access(init.io, fallback_path, .{}) catch {
                    std.debug.print("  error: host binary not found at\n    {s}\n  or\n    {s}\n  ensure the .host file is placed next to the .exe\n", .{ resolved_launch, fallback_path });
                    return error.HostBinaryMissing;
                };
                break :blk fallback_path;
            };
            break :blk resolved_launch;
        };

        const final_cwd = blk: {
            std.Io.Dir.cwd().access(init.io, resolved_cwd, .{}) catch {
                break :blk exe_dir;
            };
            break :blk resolved_cwd;
        };

        const final_launch_abs = try std.fs.path.resolve(allocator, &.{ base_cwd, final_launch });
        const final_cwd_abs = try std.fs.path.resolve(allocator, &.{ base_cwd, final_cwd });

        // Ensure host binary is executable
        {
            const launch_z = try allocator.dupeZ(u8, final_launch_abs);
            _ = std.c.chmod(launch_z.ptr, 0o755);
        }

        var final_paths_buf: [2048]u8 = undefined;
        const final_paths_msg = std.fmt.bufPrint(
            &final_paths_buf,
            "  host_bin: {s}\n  host_cwd: {s}",
            .{ final_launch_abs, final_cwd_abs },
        ) catch "";
        if (final_paths_msg.len > 0) {
            _ = std.c.write(2, final_paths_msg.ptr, final_paths_msg.len);
            _ = std.c.write(2, "\n", 1);
        }

        try setEnvValue(allocator, "ROSETTE_EXE_PATH", abs_exe_path);
        try setEnvValue(allocator, "ROSETTE_TRACE_PATH", abs_log_path);

        const status = try process_guard.run(init.io, .{
            .argv = &.{final_launch_abs},
            .cwd = final_cwd_abs,
            .stdin = .inherit,
            .stdout = .inherit,
            .stderr = .inherit,
            .label = "rosette-exe-host",
            .timeout_ms = process_guard.timeoutFromEnv(null),
        });
        var term_buf: [128]u8 = undefined;
        const term_line = try std.fmt.bufPrint(&term_buf, "launch_term = {s}\n", .{@tagName(status)});
        trace.logText(term_line);
        return;
    }

    if (launch_allowed) {
        bootLog("7_import_exec_engine: loading x86 emulation modules");
        const exec_engine = @import("../../x86-ASM/execution_engine.zig");
        const win32 = @import("../../x86-ASM/win32_thunks.zig");
        const mscoree = @import("../../x86-ASM/mscoree_thunks.zig");
        const Executor = @import("../../x86-ASM/instruction_operations.zig").Executor;

        bootLog("8_abi_x86_init: initializing ABI handshake");
        runtime_abi.x86.init();
        defer runtime_abi.x86.deinit();

        trace.logText("execution = true\n");

        bootLog("9_create_executor: allocating emulator memory");
        const stack_size: u32 = 1024 * 1024;
        const mem_size = image.size_of_image + stack_size;
        var exec = Executor.init(allocator, mem_size);
        defer exec.deinit();
        exec.setRawX86PeMode();

        bootLog("10_code_text_segments: registering executable memory regions");
        exec.mem.base = @as(u32, @truncate(image.image_base));
        installCodeTextSegments(&exec, &image);

        bootLog("11_copy_sections: writing section data to emulated memory");
        for (image.sections) |section| {
            const raw = pkg.rawSectionBytes(exe_bytes, &section);
            const dest = section.virtual_address;
            const copy_len = @min(@as(usize, section.raw_size), raw.len);
            if (dest + copy_len <= exec.mem.data.len) {
                @memcpy(exec.mem.data[dest .. dest + copy_len], raw[0..copy_len]);
            }
        }

        bootLog("12_set_registers: initializing x86 CPU state (EIP, ESP, segment regs)");
        const image_base_u32: u32 = @as(u32, @truncate(image.image_base));
        exec.regs.eip = image_base_u32 + image.entry_rva;
        exec.regs.esp = image_base_u32 + image.size_of_image + stack_size - 16;
        exec.regs.ebp = exec.regs.esp;
        exec.mem.stack_hint = exec.regs.esp;
        exec.regs.cs = 0x23;
        exec.regs.ds = 0x2B;
        exec.regs.ss = 0x2B;

        bootLog("13_register_thunks: installing Win32 & mscoree thunks");
        win32.register_win32_console_thunks(&exec);
        mscoree.register_mscoree_thunks(&exec);

        bootLog("14_parse_imports: parsing PE import directory table");
        var import_dir = imports_mod.parseImportDirectory(allocator, exe_bytes, &image) catch |err| blk: {
            var imp_buf: [256]u8 = undefined;
            const imp_line = std.fmt.bufPrint(&imp_buf, "imports = none (error={s})\n", .{@errorName(err)}) catch "";
            trace.logText(imp_line);
            break :blk null;
        };
        const managed_gui = if (import_dir) |*dir|
            image.subsystem == fmt.coff.subsystem_windows_gui and hasMscoreeEntry(dir)
        else
            false;
        if (managed_gui) {
            trace.logText("managed_gui = true\n");
        }
        bootLog("15_mscoree_env: setting CLR environment variables");
        try prepareNativeMscoreeEnvironment(allocator, exe_path, log_path, managed_gui);

        if (managed_gui) {
            bootLog("15b_managed_gui_helper: launching mscoree window helper");
            trace.logText("managed_gui_launch = detached_helper\n");
            launchManagedWindowHelper(init, allocator, exe_path, log_path) catch |err| {
                var helper_err_buf: [256]u8 = undefined;
                const helper_err = std.fmt.bufPrint(&helper_err_buf, "managed_gui_launch_error = {s}\n", .{@errorName(err)}) catch "";
                trace.logText(helper_err);
                return err;
            };
            trace.logText("guest_exit = 0x0\n");
            trace.logText("execution = false\n");

            var trace_uri_buf: [1024]u8 = undefined;
            var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
            const trace_display = blk: {
                if (!std.fs.path.isAbsolute(log_path)) break :blk log_path;
                if (std.c.getcwd(&cwd_buf, cwd_buf.len)) |cwd_ptr| {
                    const cwd_abs = std.mem.sliceTo(cwd_ptr, 0);
                    if (std.mem.startsWith(u8, log_path, cwd_abs) and log_path.len > cwd_abs.len and log_path[cwd_abs.len] == std.fs.path.sep) {
                        break :blk log_path[cwd_abs.len + 1 ..];
                    }
                }
                break :blk try writeFileUri(&trace_uri_buf, log_path);
            };

            std.debug.print(
                "Rosette EXE intake\n  file: {s}\n  machine: {s} (0x{X:0>4})\n  entry RVA: 0x{X:0>8}\n  sections: {d}\n  trace: {s}\n  managed GUI: launched mscoree window helper\n  guest exit: 0x0\n",
                .{
                    exe_path,
                    machineName(image.machine),
                    image.machine,
                    image.entry_rva,
                    image.number_of_sections,
                    trace_display,
                },
            );
            return;
        }

        // Initialize CLR runtime for managed applications
        if (false and managed_gui) { // Temporarily disabled to debug hang
            std.debug.print("CLR: Initializing runtime...\n", .{});
            try setEnvLiteral("ROSETTE_ENABLE_CLR_RUNTIME", "1");
            clr_runtime.initRuntime(allocator) catch |err| {
                std.debug.print("Failed to initialize CLR runtime: {}\n", .{err});
            };
            std.debug.print("CLR: Runtime initialized\n", .{});
            // Pass the exe file data to CLR runtime for assembly detection
            std.debug.print("CLR: Setting assembly data ({} bytes)...\n", .{exe_bytes.len});
            clr_runtime.setAssemblyData(exe_bytes) catch |err| {
                std.debug.print("Failed to set CLR assembly data: {}\n", .{err});
            };
            std.debug.print("CLR: Assembly data set\n", .{});
        }
        defer if (false and managed_gui) clr_runtime.deinitRuntime();

        bootLog("15a_iat_setup: populating import address table");
        {
            exec_engine.clearIatEntries();
            if (import_dir) |*dir| {
                var imp_buf: [256]u8 = undefined;
                const imp_line = std.fmt.bufPrint(&imp_buf, "imports = {d} entries parsed\n", .{dir.descriptors.len}) catch "";
                trace.logText(imp_line);

                for (dir.descriptors, 0..) |desc, i| {
                    if (i >= 5) break;
                    var dll_buf: [512]u8 = undefined;
                    const dll_line = std.fmt.bufPrint(&dll_buf, "import[{d}] dll={s} func={s} iat_rva=0x{X:0>8}\n", .{ i, desc.dll_name, desc.function_name, desc.iat_rva }) catch "";
                    trace.logText(dll_line);
                }

                for (dir.descriptors) |desc| {
                    const iat_addr = image_base_u32 + desc.iat_rva;
                    exec_engine.addIatEntry(iat_addr, desc.function_name);
                }
            }
        }

        bootLog("16_execution_loop: beginning x86 instruction emulation");
        var thunk_table = exec_engine.ThunkTable{};
        const entry_eip = exec.regs.eip;
        var raw_step_count: usize = 0;
        while (true) {
            if (raw_step_count % 10000 == 0) {
                var step_buf: [64]u8 = undefined;
                const step_msg = std.fmt.bufPrint(&step_buf, "16a_exec_step: {d} instructions executed", .{raw_step_count}) catch "16a_exec_step";
                bootLog(step_msg);
            }
            logRawStep(&exec);
            if (!exec_engine.execNext(&exec, &thunk_table)) break;
            raw_step_count += 1;
            if (raw_step_count >= 100000) {
                exec.regs.pending_exception = 6;
                trace.logText("halt_context = raw_step_limit steps=100000\n");
                break;
            }
        }

        bootLog("17_post_exec: post-execution diagnostics");
        if (exec.regs.eip == entry_eip) {
            {
                const base = exec.mem.base;
                const entry_off = entry_eip -| base;
                if (entry_off < exec.mem.data.len) {
                    const window_len = @min(@as(usize, 64), exec.mem.data.len - entry_off);
                    const raw_window = exec.mem.data[entry_off .. entry_off + window_len];
                    var di_off: usize = 0;
                    var di_count: u32 = 0;
                    while (di_off < raw_window.len and di_count < 8) {
                        const line = x86_disasm.decodeInstruction(entry_eip + @as(u32, @intCast(di_off)), raw_window[di_off..]) catch break;
                        di_off += line.byte_len;
                        di_count += 1;
                        var hex_buf2: [48]u8 = undefined;
                        var hpos: usize = 0;
                        for (0..line.byte_len) |j| {
                            if (j > 0) {
                                hex_buf2[hpos] = ' ';
                                hpos += 1;
                            }
                            const hi_val = line.bytes[j] >> 4;
                            const lo_val = line.bytes[j] & 0xF;
                            hex_buf2[hpos] = @as(u8, if (hi_val < 10) '0' + hi_val else 'A' + hi_val - 10);
                            hpos += 1;
                            hex_buf2[hpos] = @as(u8, if (lo_val < 10) '0' + lo_val else 'A' + lo_val - 10);
                            hpos += 1;
                        }
                        var di_buf: [256]u8 = undefined;
                        const di_line = std.fmt.bufPrint(&di_buf, "; disasm: 0x{X:0>8}: {s}  {s}\n", .{ line.address, hex_buf2[0..hpos], line.text[0..line.text_len] }) catch break;
                        trace.logText(di_line);
                    }
                }
            }
        }
        if (exec.terminated) {
            var exit_buf: [96]u8 = undefined;
            const exit_line = std.fmt.bufPrint(&exit_buf, "guest_exit = 0x{X}\n", .{exec.exit_code}) catch "";
            trace.logText(exit_line);
        } else if (exec.regs.pending_exception != 0 or exec.regs.eip == entry_eip) {
            logHaltContext(&exec);
        }

        // Execute managed code through CLR runtime after x86 emulation terminates
        bootLog("18_clr_managed: finishing managed execution path");
        if (managed_gui and exec.terminated) {
            if (comptime std.debug.runtime_safety) {
                std.log.debug("x86 emulation terminated for CLR app; starting managed execution", .{});
            }
            if (clr_runtime.getRuntime()) |rt| {
                rt.runAssembly() catch |err| {
                    std.debug.print("CLR runtime execution failed: {s}\n", .{@errorName(err)});
                };
            }
        }

        exec_engine.clearIatEntries();

        trace.logText("execution = false\n");

        var trace_uri_buf: [1024]u8 = undefined;
        var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
        const trace_display = blk: {
            if (!std.fs.path.isAbsolute(log_path)) break :blk log_path;
            if (std.c.getcwd(&cwd_buf, cwd_buf.len)) |cwd_ptr| {
                const cwd_abs = std.mem.sliceTo(cwd_ptr, 0);
                if (std.mem.startsWith(u8, log_path, cwd_abs) and log_path.len > cwd_abs.len and log_path[cwd_abs.len] == std.fs.path.sep) {
                    break :blk log_path[cwd_abs.len + 1 ..];
                }
            }
            break :blk try writeFileUri(&trace_uri_buf, log_path);
        };

        std.debug.print(
            "Rosette EXE intake\n  file: {s}\n  machine: {s} (0x{X:0>4})\n  entry RVA: 0x{X:0>8}\n  sections: {d}\n  trace: {s}\n  raw execution: stopped at 0x{X:0>8}\n",
            .{
                exe_path,
                machineName(image.machine),
                image.machine,
                image.entry_rva,
                image.number_of_sections,
                trace_display,
                exec.regs.eip,
            },
        );
        if (exec.terminated) {
            std.debug.print("  guest exit: 0x{X}\n", .{exec.exit_code});
        }
    } else {
        trace.logText("launch_skipped = parse_only\n");

        var trace_uri_buf: [1024]u8 = undefined;
        var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
        const trace_display = blk: {
            if (!std.fs.path.isAbsolute(log_path)) break :blk log_path;
            if (std.c.getcwd(&cwd_buf, cwd_buf.len)) |cwd_ptr| {
                const cwd_abs = std.mem.sliceTo(cwd_ptr, 0);
                if (std.mem.startsWith(u8, log_path, cwd_abs) and log_path.len > cwd_abs.len and log_path[cwd_abs.len] == std.fs.path.sep) {
                    break :blk log_path[cwd_abs.len + 1 ..];
                }
            }
            break :blk try writeFileUri(&trace_uri_buf, log_path);
        };

        std.debug.print(
            "Rosette EXE intake\n  file: {s}\n  machine: {s} (0x{X:0>4})\n  entry RVA: 0x{X:0>8}\n  sections: {d}\n  trace: {s}\n",
            .{
                exe_path,
                machineName(image.machine),
                image.machine,
                image.entry_rva,
                image.number_of_sections,
                trace_display,
            },
        );
    }
}
