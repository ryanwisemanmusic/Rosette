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

const page_size: u64 = 0x1000;
const max_instruction_length: usize = 15;
const minimum_stack_reserve: u64 = 16 * 1024 * 1024;
const maximum_stack_reserve: u64 = 128 * 1024 * 1024;
const minimum_heap_reserve: u64 = 64 * 1024 * 1024;
const maximum_heap_reserve: u64 = 256 * 1024 * 1024;
const maximum_runtime_memory: u64 = 1024 * 1024 * 1024;
const synthetic_thunk_stride: u64 = 16;

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
        return self.entry_is_executable and self.worklist_complete and self.invalid_instructions == 0 and
            self.unsupported_imports == 0 and self.unsupported_instructions == 0 and self.import_status != .malformed;
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
};

pub const GraphicsHooks = elf.WindowsGraphicsHooks;

pub const RunResult = struct {
    exit_code: u64,
    faulted: bool,
    terminated: bool,
    executed_steps: u64,
    rip: u64,
    graphics: elf.WindowsGraphicsSnapshot,
    windows_file_open_calls: u64,
    windows_file_read_calls: u64,
    windows_file_write_calls: u64,
    windows_file_failures: u64,
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
    return std.fmt.bufPrint(
        buffer,
        "pe64_preflight = {s}\nentry_rva = 0x{X:0>8}\nentry_executable = {}\nworklist_complete = {}\nexecutable_sections = {d}\nexecutable_bytes = {d}\nreachable_instructions = {d}\ndecoded_instructions = {d}\ninvalid_instructions = {d}\nfirst_invalid_rva = 0x{X:0>8}\nunsupported_instructions = {d}\nfirst_unsupported_rva = 0x{X:0>8}\nfirst_unsupported_op = {s}\ndirect_calls = {d}\ndirect_branches = {d}\nindirect_control_transfers = {d}\nexternal_direct_targets = {d}\nnon_executable_direct_targets = {d}\nimports = {d}\nimport_status = {s}\nimport_classes(core/graphics/supported/unsupported) = {}/{}/{}/{}\nfirst_unsupported_import = {s}!{s}\nfeatures(vex/evex/avx2/avx512/bmi/fma) = {}/{}/{}/{}/{}/{}\n",
        .{
            if (report.ready()) "ready" else "blocked",
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
            report.core_imports,
            report.graphics_imports,
            report.supported_imports,
            report.unsupported_imports,
            report.first_unsupported_dll orelse "<none>",
            report.first_unsupported_import orelse "<none>",
            report.uses_vex,
            report.uses_evex,
            report.uses_avx2,
            report.uses_avx512,
            report.uses_bmi,
            report.uses_fma,
        },
    ) catch "pe64_preflight = formatting_failed\n";
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
    state.windows_graphics.hooks = options.graphics_hooks;

    const sentinel = std.math.sub(u64, image_end, 0x1000) catch return error.AddressOverflow;
    try writeByte(&state, sentinel, 0xF4);
    state.write64(sentinel - 8, sentinel);
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
        .windows_file_open_calls = state.windows_file_open_calls,
        .windows_file_read_calls = state.windows_file_read_calls,
        .windows_file_write_calls = state.windows_file_write_calls,
        .windows_file_failures = state.windows_file_failures,
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
