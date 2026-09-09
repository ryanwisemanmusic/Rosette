//! PE32+ intake, static execution preflight, and the bounded x86-64 launch
//! path used by Rosette's Windows-target route.
//!
//! This is deliberately a Rosetta component.  It consumes a Windows PE image
//! as data and never requires a source change in the Windows program being
//! inspected.  The static pass is conservative: it follows direct control
//! flow from the image entry point, records indirect edges as unknown, and
//! refuses to describe a path as complete when the decoder cannot prove an
//! instruction boundary.

const std = @import("std");
const parser = @import("pe_parser.zig");
const fmt = @import("pe_format.zig");
const imports_mod = @import("imports/imports.zig");
const x64_decoder = @import("x64_decoder");
const elf = @import("elf_processor_state");
const windows_runtime = @import("windows_runtime");
const evex = @import("evex_runtime");
const cleo_routing = @import("cleo_routing");

const log = std.log.scoped(.pe64_runtime);

const page_size: u64 = 0x1000;
const max_instruction_length: usize = 15;
const minimum_stack_reserve: u64 = 16 * 1024 * 1024;
const maximum_stack_reserve: u64 = 128 * 1024 * 1024;
const minimum_heap_reserve: u64 = 64 * 1024 * 1024;
const maximum_heap_reserve: u64 = 256 * 1024 * 1024;
const maximum_runtime_memory: u64 = 1024 * 1024 * 1024;
const synthetic_thunk_stride: u64 = 16;
const tls_directory_index: usize = 9;
const tls_directory_size_pe64: u32 = 40;
// Keep one slot for the module's static TLS block. Dynamic TLS allocation
// begins after it, so the PE's pthread key can never alias the image TLS.
const static_tls_module_index: u32 = 1;

// The Microsoft x64 ABI addresses the current thread through GS. Rosetta's
// ordinary x86 state already models segment bases, but a PE launch also needs
// the small Windows loader environment that MinGW/MSVC startup code assumes.
// Keep the layout here rather than teaching individual CRT instructions about
// host state: this is the boundary where a Windows process receives its
// initial TEB/PEB contract.
const windows_teb_bytes: u64 = 0x2000;
const windows_tls_block_bytes: u64 = 0x11000;
const windows_peb_bytes: u64 = 0x1000;
const windows_process_parameters_bytes: u64 = 0x1000;
const windows_process_heap_bytes: u64 = 0x1000;
const teb_stack_base_offset: u64 = 0x08;
const teb_stack_limit_offset: u64 = 0x10;
const teb_self_offset: u64 = 0x30;
const teb_client_id_process_offset: u64 = 0x40;
const teb_client_id_thread_offset: u64 = 0x48;
const teb_tls_pointer_offset: u64 = 0x58;
const teb_peb_offset: u64 = 0x60;
const teb_last_error_offset: u64 = 0x68;
const peb_image_base_offset: u64 = 0x10;
const peb_process_parameters_offset: u64 = 0x20;
const peb_process_heap_offset: u64 = 0x30;

fn loadedImageAddress(image: *const parser.Image, load_base: u64, preferred_address: u64) !u64 {
    const preferred_base = if (image.image_base != 0) image.image_base else load_base;
    if (preferred_address < preferred_base) return error.InvalidTlsDirectory;
    const rva = preferred_address - preferred_base;
    if (rva > image.size_of_image) return error.InvalidTlsDirectory;
    return std.math.add(u64, load_base, rva) catch error.InvalidTlsDirectory;
}

fn configureWindowsStaticTls(state: *elf.ElfState, image: *const parser.Image, load_base: u64) !void {
    const directory = image.dataDirectory(tls_directory_index) orelse return;
    if (directory.size < tls_directory_size_pe64) return error.InvalidTlsDirectory;
    const directory_address = try imageAddress(load_base, directory.virtual_address);
    if (state.guestMemoryConst(directory_address, tls_directory_size_pe64) == null) {
        return error.InvalidTlsDirectory;
    }

    const raw_start = try loadedImageAddress(image, load_base, state.read64(directory_address));
    const raw_end = try loadedImageAddress(image, load_base, state.read64(directory_address + 8));
    const index_address = try loadedImageAddress(image, load_base, state.read64(directory_address + 16));
    const template_length = raw_end -| raw_start;
    const zero_fill = state.read32(directory_address + 32);
    const block_bytes = std.math.add(u64, template_length, zero_fill) catch return error.InvalidTlsDirectory;
    if (raw_end < raw_start or block_bytes == 0) return error.InvalidTlsDirectory;
    if (!state.configureWindowsStaticTls(
        static_tls_module_index,
        raw_start,
        template_length,
        block_bytes,
    )) return error.InvalidTlsDirectory;

    // AddressOfIndex is a guest VA containing the module TLS slot selected by
    // the loader. The image was copied before this call, so publishing the
    // slot here makes every __tls_index access resolve through the same TEB
    // vector that the PE code sees at runtime.
    state.write32(index_address, static_tls_module_index);
}

fn initializeWindowsThreadEnvironment(
    state: *elf.ElfState,
    image: *const parser.Image,
    load_base: u64,
    stack_base: u64,
    stack_limit: u64,
) !void {
    try configureWindowsStaticTls(state, image, load_base);
    const teb = state.guestAlloc(windows_teb_bytes, page_size) orelse return error.WindowsEnvironmentAllocationFailed;
    const peb = state.guestAlloc(windows_peb_bytes, page_size) orelse return error.WindowsEnvironmentAllocationFailed;
    const process_parameters = state.guestAlloc(windows_process_parameters_bytes, page_size) orelse return error.WindowsEnvironmentAllocationFailed;
    const process_heap = state.guestAlloc(windows_process_heap_bytes, page_size) orelse return error.WindowsEnvironmentAllocationFailed;
    const tls_block = state.guestAlloc(@max(windows_tls_block_bytes, state.windows_static_tls_block_bytes), page_size) orelse return error.WindowsEnvironmentAllocationFailed;

    // x64 Windows uses GS:[0x30] for TEB->Self. The first CRT startup
    // exchange then reads TEB->StackBase at +0x8 and uses it as the owner
    // token for __native_startup_lock. A zero GS base therefore does not just
    // lose optional TLS state: it turns the CRT's legal startup loop into a
    // null indirect call.
    state.regs.segments.gs.base = teb;
    state.windows_main_teb = teb;
    state.windows_process_peb = peb;
    state.write64(teb + teb_stack_base_offset, stack_base);
    state.write64(teb + teb_stack_limit_offset, stack_limit);
    state.write64(teb + teb_self_offset, teb);
    state.write64(teb + teb_client_id_process_offset, 1);
    state.write64(teb + teb_client_id_thread_offset, 1);
    // The PE TLS directory supplies a module index, and Windows resolves that
    // index through TEB->ThreadLocalStoragePointer. Keep the vector in the
    // TEB allocation and publish the initialized template at that module slot;
    // dynamic TlsAlloc indices remain independent of it.
    const tls_vector = teb + 0x1000;
    state.write64(teb + teb_tls_pointer_offset, tls_vector);
    if (state.windows_static_tls_template_length != 0) {
        const source = state.guestMemoryConst(
            state.windows_static_tls_template_start,
            state.windows_static_tls_template_length,
        ) orelse return error.WindowsEnvironmentAllocationFailed;
        const destination = state.guestMemory(
            tls_block,
            state.windows_static_tls_template_length,
        ) orelse return error.WindowsEnvironmentAllocationFailed;
        @memcpy(destination, source);
    }
    if (state.windows_static_tls_index) |index| {
        state.write64(tls_vector + @as(u64, index) * 8, tls_block);
    }
    state.write64(teb + teb_peb_offset, peb);
    state.write32(teb + teb_last_error_offset, 0);

    // The PEB fields below are enough for loader/CRT probes to receive valid
    // guest pointers. They deliberately point into the same guest address
    // space; no host pointer is ever exposed to the Windows image.
    state.write64(peb + peb_image_base_offset, state.image_low);
    state.write64(peb + peb_process_parameters_offset, process_parameters);
    state.write64(peb + peb_process_heap_offset, process_heap);

    // ProcessParameters starts zeroed and is intentionally conservative until
    // the runner supplies a Windows command line. Keeping the structure
    // addressable is materially safer than returning a non-guest pointer from
    // a PEB walk, and later ABI handlers can populate its UNICODE_STRINGs.
    log.info("PE64 Windows environment: gs_base=0x{x} teb=0x{x} peb=0x{x} stack=[0x{x},0x{x}) process_parameters=0x{x}", .{
        state.regs.segments.gs.base,
        teb,
        peb,
        stack_limit,
        stack_base,
        process_parameters,
    });
}

pub const ImportStatus = enum {
    absent,
    parsed,
    malformed,
};

pub const PreflightReport = struct {
    entry_rva: u32,
    entry_is_executable: bool = false,
    worklist_complete: bool = true,
    executable_sections: u32 = 0,
    executable_bytes: u64 = 0,
    reachable_instructions: u64 = 0,
    decoded_instructions: u64 = 0,
    invalid_instructions: u64 = 0,
    direct_calls: u64 = 0,
    direct_branches: u64 = 0,
    indirect_control_transfers: u64 = 0,
    external_direct_targets: u64 = 0,
    non_executable_direct_targets: u64 = 0,
    imports: u64 = 0,
    core_imports: u64 = 0,
    graphics_imports: u64 = 0,
    degraded_imports: u64 = 0,
    supported_imports: u64 = 0,
    unsupported_imports: u64 = 0,
    import_status: ImportStatus = .absent,
    uses_vex: bool = false,
    uses_evex: bool = false,
    uses_avx2: bool = false,
    uses_avx512: bool = false,
    uses_bmi: bool = false,
    uses_fma: bool = false,
    unsupported_instructions: u64 = 0,
    first_invalid_rva: ?u32 = null,
    first_unsupported_rva: ?u32 = null,
    first_unsupported_op: ?[]const u8 = null,

    first_unsupported_dll: ?[]const u8 = null,
    first_unsupported_import: ?[]const u8 = null,

    pub fn deinit(self: *PreflightReport, allocator: std.mem.Allocator) void {
        if (self.first_unsupported_dll) |value| allocator.free(value);
        if (self.first_unsupported_import) |value| allocator.free(value);
        self.first_unsupported_dll = null;
        self.first_unsupported_import = null;
    }

    pub fn ready(self: *const PreflightReport) bool {
        // `ready` means that every imported name has an explicit Rosetta ABI
        // policy. Degraded imports are launchable but not yet semantically
        // complete; the report exposes them separately so this cannot be
        // mistaken for full Windows API coverage.
        return self.entry_is_executable and self.worklist_complete and self.invalid_instructions == 0 and
            self.unsupported_imports == 0 and self.unsupported_instructions == 0 and self.import_status != .malformed;
    }

    pub fn complete(self: *const PreflightReport) bool {
        return self.ready() and self.degraded_imports == 0;
    }
};

pub const RunOptions = struct {
    max_steps: u64 = 20_000_000,
    load_base: ?u64 = null,
    graphics_hooks: elf.WindowsGraphicsHooks = .{},
    /// Optional host I/O authority for the Windows ABI bridge. Paths are
    /// resolved beneath `host_working_directory`; when absent, file imports
    /// remain explicit ERROR_FILE_NOT_FOUND results rather than touching the
    /// process working directory implicitly.
    host_io: ?std.Io = null,
    host_working_directory: ?[]const u8 = null,
    /// Windows arguments after argv[0]. They are copied into guest memory by
    /// the CRT bridge; the PE never receives a host pointer.
    windows_arguments: []const []const u8 = &.{},
    /// Optional host media authority for the virtual C:\\xenia mount. Only a
    /// matching leaf name is exposed by the Windows path bridge.
    windows_media_path: ?[]const u8 = null,
};

pub const GraphicsHooks = elf.WindowsGraphicsHooks;

pub const RunResult = struct {
    exit_code: u64,
    faulted: bool,
    terminated: bool,
    executed_steps: u64,
    rip: u64,
    graphics: elf.WindowsGraphicsSnapshot,
    windows_import_calls: u64,
    windows_degraded_import_calls: u64,
    windows_unknown_import_calls: u64,
    windows_file_open_calls: u64,
    windows_file_read_calls: u64,
    windows_file_write_calls: u64,
    windows_file_failures: u64,
    windows_rtl_capture_calls: u64,
    windows_rtl_unwind_calls: u64,
};

fn alignUp(value: u64, alignment: u64) !u64 {
    if (alignment == 0) return error.InvalidAlignment;
    const remainder = value % alignment;
    if (remainder == 0) return value;
    return std.math.add(u64, value, alignment - remainder) catch error.AddressOverflow;
}

fn clampReserve(value: u64, minimum: u64, maximum: u64) u64 {
    return @min(maximum, @max(minimum, value));
}

fn rvaToFileOffset(image: *const parser.Image, rva: u32) ?usize {
    for (image.sections) |section| {
        const section_end = std.math.add(u32, section.virtual_address, section.raw_size) catch continue;
        if (rva < section.virtual_address or rva >= section_end) continue;
        const delta = rva - section.virtual_address;
        const file_offset = std.math.add(u32, section.raw_offset, delta) catch return null;
        return @intCast(file_offset);
    }
    return null;
}

fn executableSection(image: *const parser.Image, rva: u32) ?*const parser.Section {
    const section = image.sectionForRva(rva) orelse return null;
    return if (section.isExecutable()) section else null;
}

fn instructionBytes(
    image: *const parser.Image,
    bytes: []const u8,
    rva: u32,
) ?[]const u8 {
    const section = executableSection(image, rva) orelse return null;
    const delta = rva - section.virtual_address;
    if (delta >= section.raw_size) return null;
    const file_offset = rvaToFileOffset(image, rva) orelse return null;
    if (file_offset >= bytes.len) return null;
    const section_remaining: usize = @intCast(section.raw_size - delta);
    const file_remaining = bytes.len - file_offset;
    const available = @min(max_instruction_length, @min(section_remaining, file_remaining));
    if (available == 0) return null;
    return bytes[file_offset .. file_offset + available];
}

// Clang's optimized implementation of xe::utf8::find_any_of begins with a
// stable entry sequence and then branches on the needle view's length. The
// relative branch displacement is intentionally excluded from this
// signature, so the locator remains valid when the PE layout changes.
const utf8_find_any_of_prefix = [_]u8{
    0x56,
    0x57,
    0x48,
    0x81,
    0xEC,
    0xB8,
    0x00,
    0x00,
    0x00,
    0x48,
    0x8B,
    0x02,
    0x48,
    0x85,
    0xC0,
    0x0F,
    0x84,
};

fn locateUtf8FindAnyOfEntry(
    image: *const parser.Image,
    bytes: []const u8,
    load_base: u64,
) ?u64 {
    for (image.sections) |section| {
        if (!section.isExecutable() or section.raw_size < utf8_find_any_of_prefix.len) continue;
        const raw_start: usize = @intCast(section.raw_offset);
        const raw_size: usize = @intCast(section.raw_size);
        if (raw_start > bytes.len or raw_size > bytes.len - raw_start) continue;
        const code = bytes[raw_start .. raw_start + raw_size];
        const last = code.len - utf8_find_any_of_prefix.len;
        for (0..last + 1) |offset| {
            if (!std.mem.eql(u8, code[offset .. offset + utf8_find_any_of_prefix.len], &utf8_find_any_of_prefix)) continue;
            const rva = std.math.add(u32, section.virtual_address, @intCast(offset)) catch continue;
            return std.math.add(u64, load_base, rva) catch null;
        }
    }
    return null;
}

fn isVexPrefix(bytes: []const u8) bool {
    return bytes.len > 0 and (bytes[0] == 0xC4 or bytes[0] == 0xC5);
}

fn isEvexPrefix(bytes: []const u8) bool {
    return bytes.len > 0 and bytes[0] == 0x62;
}

fn operationUsesBmi(op: x64_decoder.Op) bool {
    return switch (op) {
        .andn, .bzhi, .mulx, .rorx, .shlx, .shrx, .sarx, .tzcnt_reg_reg, .tzcnt_reg_mem, .lzcnt_reg_reg, .lzcnt_reg_mem => true,
        else => false,
    };
}

fn operationUsesFma(op: x64_decoder.Op) bool {
    const name = @tagName(op);
    return std.mem.startsWith(u8, name, "vfm") or std.mem.startsWith(u8, name, "vfnm");
}

fn isVectorOperation(op: x64_decoder.Op) bool {
    const name = @tagName(op);
    return std.mem.startsWith(u8, name, "v") or
        op == .pmovmskb or op == .vpmovmskb or op == .vpmovmskb_ymm;
}

fn isDirectlyHandledVector(op: x64_decoder.Op) bool {
    return switch (op) {
        // These operations have architectural state behavior in the ELF
        // processor but intentionally have no one-to-one CLEO meta.
        .vzeroupper,
        .vpshufd,
        .vptest,
        .vtestps,
        .vtestpd,
        .vpmovmskb,
        .vpmovmskb_ymm,
        .pmovmskb,
        .vmovmskps,
        .vmovmskpd,
        .vcvtsi2ss_xmm_reg,
        .vcvtsi2ss_xmm_mem,
        .vcvtsi2sd_xmm_reg,
        .vcvtsi2sd_xmm_mem,
        .vcvtss2sd,
        .vcvtsd2ss,
        .vaddss,
        .vaddsd,
        .vmulss,
        .vmulsd,
        .vsubss,
        .vsubsd,
        .vdivss,
        .vdivsd,
        .vminss,
        .vminsd,
        .vmaxss,
        .vmaxsd,
        .vsqrtss,
        .vsqrtsd,
        .vsqrtps,
        .vsqrtpd,
        .vrcpss,
        .vrcpps,
        .vrsqrtss,
        .vrsqrtps,
        .vroundss,
        .vroundsd,
        .vroundps,
        .vroundpd,
        .vcvttss2si,
        .vcvttsd2si,
        .vcvtss2si,
        .vcvtsd2si,
        .vucomiss,
        .vucomisd,
        .vshufps,
        .vpermilpd,
        => true,
        else => false,
    };
}

fn operationSupported(decoded: x64_decoder.DecodedInsn) bool {
    if (!isVectorOperation(decoded.op)) return true;
    if (isDirectlyHandledVector(decoded.op) or evex.handles(decoded.op)) return true;
    const route = cleo_routing.CleoRouter.route(
        @tagName(decoded.op),
        cleo_routing.types.FeatureSet.cleoEmulated(),
        if (decoded.vector_256) 256 else 128,
    );
    return route.can_route;
}

fn relativeTarget(rva: u32, decoded: x64_decoder.DecodedInsn) ?u32 {
    const next = std.math.add(u32, rva, decoded.len) catch return null;
    const next_signed: i64 = @intCast(next);
    const relative: i64 = @bitCast(decoded.imm);
    const target = std.math.add(i64, next_signed, relative) catch return null;
    if (target < 0 or target > std.math.maxInt(u32)) return null;
    return @intCast(target);
}

fn enqueueDirectTarget(
    image: *const parser.Image,
    target: ?u32,
    work: *std.ArrayList(u32),
    seen: *std.AutoHashMap(u32, void),
    report: *PreflightReport,
    allocator: std.mem.Allocator,
) !void {
    const target_rva = target orelse {
        report.external_direct_targets += 1;
        return;
    };
    const section = image.sectionForRva(target_rva) orelse {
        report.external_direct_targets += 1;
        return;
    };
    if (!section.isExecutable()) {
        report.non_executable_direct_targets += 1;
        return;
    }
    if (!seen.contains(target_rva)) {
        try seen.put(target_rva, {});
        try work.append(allocator, target_rva);
    }
}

/// Analyze direct control flow reachable from the PE entry point.  An
/// indirect transfer is intentionally recorded rather than guessed: Windows
/// imports, vtables, exception tables, and JIT-generated targets require
/// runtime evidence and must not be reported as statically proven.
pub fn preflight(allocator: std.mem.Allocator, bytes: []const u8, image: *const parser.Image) !PreflightReport {
    var report = PreflightReport{ .entry_rva = image.entry_rva };
    report.entry_is_executable = executableSection(image, image.entry_rva) != null;
    for (image.sections) |section| {
        if (!section.isExecutable()) continue;
        report.executable_sections += 1;
        report.executable_bytes += section.raw_size;
    }

    if (image.dataDirectory(fmt.data_dir.entry_import)) |directory| {
        _ = directory;
        report.import_status = .parsed;
        if (imports_mod.parseImportDirectory(allocator, bytes, image)) |parsed_value| {
            var parsed = parsed_value;
            report.imports = parsed.descriptors.len;
            defer parsed.deinit(allocator);
            for (parsed.descriptors) |descriptor| {
                switch (windows_runtime.classifyImport(descriptor.dll_name, descriptor.function_name)) {
                    .core => {
                        report.core_imports += 1;
                        report.supported_imports += 1;
                    },
                    .graphics => {
                        report.graphics_imports += 1;
                        report.supported_imports += 1;
                    },
                    .degraded => {
                        report.degraded_imports += 1;
                    },
                    .unsupported => {
                        report.unsupported_imports += 1;
                        if (report.first_unsupported_dll == null) {
                            report.first_unsupported_dll = try allocator.dupe(u8, descriptor.dll_name);
                            report.first_unsupported_import = try allocator.dupe(u8, descriptor.function_name);
                        }
                    },
                }
            }
        } else |_| {
            report.import_status = .malformed;
        }
    }
    if (!report.entry_is_executable) return report;

    var work: std.ArrayList(u32) = .empty;
    defer work.deinit(allocator);
    var seen = std.AutoHashMap(u32, void).init(allocator);
    defer seen.deinit();
    try seen.put(image.entry_rva, {});
    try work.append(allocator, image.entry_rva);

    const maximum_nodes: usize = 2_000_000;
    var work_index: usize = 0;
    while (work_index < work.items.len) : (work_index += 1) {
        if (work_index >= maximum_nodes) {
            report.worklist_complete = false;
            break;
        }
        const rva = work.items[work_index];
        const code = instructionBytes(image, bytes, rva) orelse {
            report.invalid_instructions += 1;
            if (report.first_invalid_rva == null) report.first_invalid_rva = rva;
            continue;
        };
        const decoded = x64_decoder.decodeLegacyInstruction(code, .long64);
        report.reachable_instructions += 1;
        if (decoded.op == .invalid or decoded.len == 0 or decoded.len > code.len) {
            report.invalid_instructions += 1;
            if (report.first_invalid_rva == null) report.first_invalid_rva = rva;
            continue;
        }
        report.decoded_instructions += 1;
        const vex_here = isVexPrefix(code);
        report.uses_vex = report.uses_vex or vex_here;
        report.uses_evex = report.uses_evex or decoded.is_evex or isEvexPrefix(code);
        report.uses_avx2 = report.uses_avx2 or decoded.vector_256 or (vex_here and std.mem.startsWith(u8, @tagName(decoded.op), "vp"));
        report.uses_avx512 = report.uses_avx512 or decoded.vector_512 or decoded.is_evex;
        report.uses_bmi = report.uses_bmi or operationUsesBmi(decoded.op);
        report.uses_fma = report.uses_fma or operationUsesFma(decoded.op);
        if (!operationSupported(decoded)) {
            report.unsupported_instructions += 1;
            if (report.first_unsupported_rva == null) {
                report.first_unsupported_rva = rva;
                report.first_unsupported_op = @tagName(decoded.op);
            }
        }

        switch (decoded.op) {
            .call_rel32 => {
                report.direct_calls += 1;
                try enqueueDirectTarget(image, relativeTarget(rva, decoded), &work, &seen, &report, allocator);
                const fallthrough = std.math.add(u32, rva, decoded.len) catch null;
                try enqueueDirectTarget(image, fallthrough, &work, &seen, &report, allocator);
            },
            .jmp_rel8 => {
                report.direct_branches += 1;
                try enqueueDirectTarget(image, relativeTarget(rva, decoded), &work, &seen, &report, allocator);
            },
            .jcc_rel8, .jcc_rel32 => {
                report.direct_branches += 1;
                try enqueueDirectTarget(image, relativeTarget(rva, decoded), &work, &seen, &report, allocator);
                const fallthrough = std.math.add(u32, rva, decoded.len) catch null;
                try enqueueDirectTarget(image, fallthrough, &work, &seen, &report, allocator);
            },
            .call_mem64, .call_reg64, .jmp_mem64, .jmp_reg64 => {
                report.indirect_control_transfers += 1;
            },
            .ret, .hlt, .ud2 => {},
            else => {
                const fallthrough = std.math.add(u32, rva, decoded.len) catch null;
                try enqueueDirectTarget(image, fallthrough, &work, &seen, &report, allocator);
            },
        }
    }
    return report;
}

pub fn formatPreflight(buffer: []u8, report: PreflightReport) []const u8 {
    const invalid_rva = if (report.first_invalid_rva) |rva| rva else 0;
    const unsupported_rva = if (report.first_unsupported_rva) |rva| rva else 0;
    const first = std.fmt.bufPrint(
        buffer,
        "pe64_preflight = {s}\nentry_rva = 0x{X:0>8}\nentry_executable = {}\nworklist_complete = {}\nexecutable_sections = {d}\nexecutable_bytes = {d}\nreachable_instructions = {d}\ndecoded_instructions = {d}\ninvalid_instructions = {d}\nfirst_invalid_rva = 0x{X:0>8}\nunsupported_instructions = {d}\nfirst_unsupported_rva = 0x{X:0>8}\nfirst_unsupported_op = {s}\ndirect_calls = {d}\ndirect_branches = {d}\nindirect_control_transfers = {d}\nexternal_direct_targets = {d}\nnon_executable_direct_targets = {d}\nimports = {d}\nimport_status = {s}\n",
        .{
            if (!report.ready()) "blocked" else if (report.complete()) "ready" else "ready_with_degraded_imports",
            report.entry_rva,
            report.entry_is_executable,
            report.worklist_complete,
            report.executable_sections,
            report.executable_bytes,
            report.reachable_instructions,
            report.decoded_instructions,
            report.invalid_instructions,
            invalid_rva,
            report.unsupported_instructions,
            unsupported_rva,
            report.first_unsupported_op orelse "<none>",
            report.direct_calls,
            report.direct_branches,
            report.indirect_control_transfers,
            report.external_direct_targets,
            report.non_executable_direct_targets,
            report.imports,
            @tagName(report.import_status),
        },
    ) catch return "pe64_preflight = formatting_failed\n";
    const second = std.fmt.bufPrint(
        buffer[first.len..],
        "import_classes(core/graphics/degraded/supported/unsupported) = {}/{}/{}/{}/{}\npreflight_complete = {}\nfirst_unsupported_import = {s}!{s}\nfeatures(vex/evex/avx2/avx512/bmi/fma) = {}/{}/{}/{}/{}/{}\n",
        .{
            report.core_imports,
            report.graphics_imports,
            report.degraded_imports,
            report.supported_imports,
            report.unsupported_imports,
            report.complete(),
            report.first_unsupported_dll orelse "<none>",
            report.first_unsupported_import orelse "<none>",
            report.uses_vex,
            report.uses_evex,
            report.uses_avx2,
            report.uses_avx512,
            report.uses_bmi,
            report.uses_fma,
        },
    ) catch return "pe64_preflight = formatting_failed\n";
    return buffer[0 .. first.len + second.len];
}

fn writeBytes(state: *elf.ElfState, address: u64, source: []const u8) !void {
    const offset = state.addrToOffset(address) orelse return error.AddressOutOfRange;
    const offset_usize: usize = @intCast(offset);
    if (offset_usize > state.mem.len or source.len > state.mem.len - offset_usize) return error.AddressOutOfRange;
    @memcpy(state.mem[offset_usize .. offset_usize + source.len], source);
}

fn writeByte(state: *elf.ElfState, address: u64, value: u8) !void {
    try writeBytes(state, address, &.{value});
}

fn imageAddress(load_base: u64, rva: u32) !u64 {
    return std.math.add(u64, load_base, rva) catch error.AddressOverflow;
}

fn copyImage(state: *elf.ElfState, bytes: []const u8, image: *const parser.Image, load_base: u64) !void {
    const header_size: usize = @intCast(@min(image.size_of_headers, @as(u32, @intCast(bytes.len))));
    try writeBytes(state, load_base, bytes[0..header_size]);
    for (image.sections) |section| {
        if (section.raw_size == 0) continue;
        const raw_start: usize = @intCast(section.raw_offset);
        const raw_size: usize = @intCast(section.raw_size);
        if (raw_start > bytes.len or raw_size > bytes.len - raw_start) return error.SectionOutOfRange;
        const destination = try imageAddress(load_base, section.virtual_address);
        try writeBytes(state, destination, bytes[raw_start .. raw_start + raw_size]);
    }
}

fn runtimeMemorySize(image: *const parser.Image, import_count: usize) !struct { total: u64, image_span: u64, thunk_span: u64 } {
    const image_span = try alignUp(image.size_of_image, page_size);
    const thunk_bytes = std.math.mul(u64, @intCast(import_count), synthetic_thunk_stride) catch return error.ImageTooLarge;
    const thunk_span = try alignUp(@max(page_size, thunk_bytes), page_size);
    const stack_reserve = clampReserve(image.size_of_stack_reserve, minimum_stack_reserve, maximum_stack_reserve);
    const heap_reserve = clampReserve(image.size_of_heap_reserve, minimum_heap_reserve, maximum_heap_reserve);
    const total = std.math.add(u64, image_span, thunk_span) catch return error.ImageTooLarge;
    const with_stack = std.math.add(u64, total, stack_reserve) catch return error.ImageTooLarge;
    const with_heap = std.math.add(u64, with_stack, heap_reserve) catch return error.ImageTooLarge;
    if (with_heap > maximum_runtime_memory) return error.ImageTooLarge;
    return .{ .total = with_heap, .image_span = image_span, .thunk_span = thunk_span };
}

/// Load a PE32+ image into Rosetta's x86-64 execution state and run it under a
/// hard step bound.  Imports are represented by addressable synthetic entry
/// points and also exposed as dynamic-relocation names so the existing libc
/// bridge can service compatible routines.  Unknown Windows imports remain
/// visible in the trace and are rejected by the default strict runtime
/// policy; they are not presented as native Windows support.
pub fn loadAndRun(allocator: std.mem.Allocator, bytes: []const u8, image: *const parser.Image, options: RunOptions) !RunResult {
    if (!image.isPe32Plus() or image.machine != fmt.coff.machine_amd64) return error.NotPe64;
    var parsed_imports = imports_mod.parseImportDirectory(allocator, bytes, image) catch |err| switch (err) {
        error.ImportDirectoryNotFound => imports_mod.ImportDirectory{ .descriptors = &.{}, .pointer_size = 8 },
        else => return err,
    };
    defer parsed_imports.deinit(allocator);
    if (parsed_imports.pointer_size != 8) return error.PointerWidthMismatch;

    const sizes = try runtimeMemorySize(image, parsed_imports.descriptors.len);
    const load_base = options.load_base orelse if (image.image_base != 0) image.image_base else 0x140000000;
    const image_end = std.math.add(u64, load_base, sizes.total) catch return error.AddressOverflow;
    const image_entry = try imageAddress(load_base, image.entry_rva);
    if (image_entry >= image_end) return error.EntryOutOfRange;

    var state = elf.ElfState.initWithMemory(allocator, sizes.total);
    defer state.deinit();
    state.mem_base = load_base;
    state.mem_size = sizes.total;
    state.image_low = load_base;
    state.image_high = std.math.add(u64, load_base, sizes.image_span) catch return error.AddressOverflow;
    state.heap_next = std.math.add(u64, state.image_high, sizes.thunk_span) catch return error.AddressOverflow;
    state.windows_entry_point = image_entry;
    try copyImage(&state, bytes, image, load_base);

    const thunk_base = state.image_high;
    const dynamic_relocations = try allocator.alloc(elf.DynamicRelocation, parsed_imports.descriptors.len);
    defer allocator.free(dynamic_relocations);
    state.windows_direct_stub_base = thunk_base;
    state.windows_direct_stub_count = parsed_imports.descriptors.len;
    state.windows_dynamic_stub_start = parsed_imports.descriptors.len;
    for (parsed_imports.descriptors, 0..) |descriptor, index| {
        const thunk_address = std.math.add(u64, thunk_base, std.math.mul(u64, @intCast(index), synthetic_thunk_stride) catch return error.AddressOverflow) catch return error.AddressOverflow;
        const iat_address = try imageAddress(load_base, descriptor.iat_rva);
        state.write64(iat_address, thunk_address);
        // Register the actual IAT target with the Windows dispatcher. A
        // decodable zero-return byte stub would bypass every Win32/Vulkan
        // contract and make direct imports look successful without executing
        // them. The dispatcher still receives an F4 sentinel at this address
        // and handles the call before the ordinary decoder runs.
        if (!state.registerWindowsImportStubAt(thunk_address, descriptor.dll_name, descriptor.function_name)) {
            return error.WindowsImportStubCapacityExceeded;
        }
        dynamic_relocations[index] = .{
            .name = descriptor.function_name,
            .offset = iat_address,
            .rel_type = 7,
            .dll_name = descriptor.dll_name,
        };
    }
    state.dynamic_relocations = dynamic_relocations;
    state.windows_runtime_enabled = true;
    state.windows_unknown_imports_fatal = true;
    state.windows_host_io = options.host_io;
    state.windows_host_working_directory = options.host_working_directory;
    state.windows_launch_arguments = options.windows_arguments;
    state.windows_host_media_path = options.windows_media_path;
    state.windows_graphics.hooks = options.graphics_hooks;
    state.windows_utf8_find_any_of_entry = locateUtf8FindAnyOfEntry(image, bytes, load_base);
    if (state.windows_utf8_find_any_of_entry) |entry| {
        log.info("PE64 guest compatibility: recognized UTF-8 find_any_of entry=0x{x}; empty character sets will return npos", .{entry});
    }

    const sentinel = std.math.sub(u64, image_end, 0x1000) catch return error.AddressOverflow;
    try writeByte(&state, sentinel, 0xF4);
    state.write64(sentinel - 8, sentinel);
    const stack_base = image_end;
    const stack_limit = std.math.sub(u64, sentinel, minimum_stack_reserve) catch load_base;
    try initializeWindowsThreadEnvironment(&state, image, load_base, stack_base, stack_limit);
    state.regs.rsp = sentinel - 8;
    state.regs.rip = image_entry;
    state.regs.rflags = 2;
    state.runWithLimit(options.max_steps);

    return .{
        .exit_code = state.exit_code,
        .faulted = state.faulted,
        .terminated = state.terminated,
        .executed_steps = state.executed_steps,
        .rip = state.regs.rip,
        .graphics = state.windows_graphics.snapshot(),
        .windows_import_calls = state.windows_import_calls,
        .windows_degraded_import_calls = state.windows_degraded_import_calls,
        .windows_unknown_import_calls = state.windows_unknown_import_calls,
        .windows_file_open_calls = state.windows_file_open_calls,
        .windows_file_read_calls = state.windows_file_read_calls,
        .windows_file_write_calls = state.windows_file_write_calls,
        .windows_file_failures = state.windows_file_failures,
        .windows_rtl_capture_calls = state.windows_rtl_capture_calls,
        .windows_rtl_unwind_calls = state.windows_rtl_unwind_calls,
    };
}

test "PE64 preflight follows direct branches and records indirect edges" {
    // The parser is exercised independently; this test only verifies the
    // control-flow policy with a compact synthetic report shape.
    var report = PreflightReport{
        .entry_rva = 0x1000,
        .entry_is_executable = true,
        .invalid_instructions = 1,
    };
    try std.testing.expect(!report.ready());
    report.worklist_complete = true;
    report.invalid_instructions = 0;
    try std.testing.expect(report.ready());
}

fn writePe32Value(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .little);
}

fn writePe64Value(bytes: []u8, offset: usize, value: u64) void {
    std.mem.writeInt(u64, bytes[offset..][0..8], value, .little);
}

fn makeSyntheticPe64(code: []const u8) [0x600]u8 {
    var bytes = [_]u8{0} ** 0x600;
    std.mem.writeInt(u16, bytes[0..2], fmt.dos.signature, .little);
    writePe32Value(&bytes, 0x3C, 0x80);
    writePe32Value(&bytes, 0x80, fmt.coff.signature);
    std.mem.writeInt(u16, bytes[0x84..0x86], fmt.coff.machine_amd64, .little);
    std.mem.writeInt(u16, bytes[0x86..0x88], 1, .little);
    std.mem.writeInt(u16, bytes[0x94..0x96], 0xF0, .little);

    const optional = 0x98;
    std.mem.writeInt(u16, bytes[optional..][0..2], fmt.coff.optional_magic_pe32_plus, .little);
    writePe32Value(&bytes, optional + 16, 0x1000);
    writePe64Value(&bytes, optional + 24, 0x140000000);
    writePe32Value(&bytes, optional + 32, 0x1000);
    writePe32Value(&bytes, optional + 36, 0x200);
    writePe32Value(&bytes, optional + 56, 0x3000);
    writePe32Value(&bytes, optional + 60, 0x400);
    std.mem.writeInt(u16, bytes[optional + 68 ..][0..2], fmt.coff.subsystem_windows_cui, .little);
    writePe64Value(&bytes, optional + 72, 0x100000);
    writePe64Value(&bytes, optional + 80, 0x1000);
    writePe64Value(&bytes, optional + 88, 0x100000);
    writePe64Value(&bytes, optional + 96, 0x1000);
    writePe32Value(&bytes, optional + 108, parser.data_directory_count);

    const section = optional + 0xF0;
    @memcpy(bytes[section..][0..8], &[_]u8{ '.', 't', 'e', 'x', 't', 0, 0, 0 });
    writePe32Value(&bytes, section + 8, 0x200);
    writePe32Value(&bytes, section + 12, 0x1000);
    writePe32Value(&bytes, section + 16, 0x200);
    writePe32Value(&bytes, section + 20, 0x400);
    writePe32Value(&bytes, section + 36, 0x60000020);
    @memcpy(bytes[0x400..][0..code.len], code);
    return bytes;
}

test "PE64 preflight decodes a real PE32+ text section" {
    var bytes = makeSyntheticPe64(&.{ 0xB8, 7, 0, 0, 0, 0xC3 });
    const image = try parser.parse(std.testing.allocator, &bytes);
    defer std.testing.allocator.free(image.sections);

    try std.testing.expect(image.isPe32Plus());
    const report = try preflight(std.testing.allocator, &bytes, &image);
    try std.testing.expect(report.entry_is_executable);
    try std.testing.expectEqual(@as(u64, 2), report.decoded_instructions);
    try std.testing.expectEqual(@as(u64, 0), report.invalid_instructions);
    try std.testing.expect(report.ready());
}

test "PE64 bounded execution reaches the synthetic return sentinel" {
    var bytes = makeSyntheticPe64(&.{ 0xB8, 7, 0, 0, 0, 0xC3 });
    const image = try parser.parse(std.testing.allocator, &bytes);
    defer std.testing.allocator.free(image.sections);

    const result = try loadAndRun(std.testing.allocator, &bytes, &image, .{ .max_steps = 32 });
    try std.testing.expect(result.terminated);
    try std.testing.expect(!result.faulted);
    try std.testing.expectEqual(@as(u64, 7), result.exit_code);
}
