const std = @import("std");
const cpu_mod = @import("cpu_state.zig");
const mem_mod = @import("segmented_memory.zig");
const runtime_abi = @import("runtime_abi_handshake");
const psp_trace = @import("../psp/runtime.zig");

const MzHeader = struct {
    bytes_in_last_page: u16,
    page_count: u16,
    relocation_count: u16,
    header_paragraphs: u16,
    min_alloc_paragraphs: u16,
    max_alloc_paragraphs: u16,
    initial_ss: u16,
    initial_sp: u16,
    checksum: u16,
    initial_ip: u16,
    initial_cs: u16,
    relocation_table_offset: u16,
    overlay_number: u16,
};

fn le16(bytes: []const u8, offset: usize) u16 {
    return @as(u16, bytes[offset]) | (@as(u16, bytes[offset + 1]) << 8);
}

pub const ImageKind = enum {
    source_reference,
    com,
    mz,
};

pub const LoadedProgram = struct {
    kind: ImageKind,
    psp_segment: u16,
    load_segment: u16,
    entry_cs: u16,
    entry_ip: u16,
    stack_ss: u16,
    stack_sp: u16,
};

pub fn initPsp(mem: *mem_mod.RealModeMemory, psp_segment: u16) !void {
    try mem.fill(psp_segment, 0x0000, 256, 0);
    try mem.write8(psp_segment, 0x0000, 0xCD);
    try mem.write8(psp_segment, 0x0001, 0x20);
    try mem.write16(psp_segment, 0x002C, psp_segment + 0x20);
    try mem.write8(psp_segment, 0x0080, 0);
    try mem.write8(psp_segment, 0x0081, 0x0D);
    runtime_abi.dos.validatePsp(
        mem.bytes.len,
        psp_segment,
        psp_segment + 0x20,
        0,
        psp_segment,
        0x0080,
        0xCD,
        0x20,
    );
    psp_trace.logPsp("initPsp", psp_segment, psp_segment + 0x20, 0, psp_segment, 0x0080);
}

pub fn loadCom(
    mem: *mem_mod.RealModeMemory,
    cpu: *cpu_mod.CpuState,
    image: []const u8,
    load_segment: u16,
) !LoadedProgram {
    try initPsp(mem, load_segment);
    try mem.writeBytes(load_segment, 0x0100, image);

    cpu.cs = load_segment;
    cpu.ds = load_segment;
    cpu.es = load_segment;
    cpu.ss = load_segment;
    cpu.ip = 0x0100;
    cpu.sp = 0xFFFE;

    const loaded: LoadedProgram = .{
        .kind = .com,
        .psp_segment = load_segment,
        .load_segment = load_segment,
        .entry_cs = load_segment,
        .entry_ip = 0x0100,
        .stack_ss = load_segment,
        .stack_sp = 0xFFFE,
    };
    runtime_abi.dos.validateLoad("com", mem.bytes.len, loaded.psp_segment, loaded.load_segment, loaded.entry_cs, loaded.entry_ip, loaded.stack_ss, loaded.stack_sp);
    return loaded;
}

pub fn loadSourceReference(
    mem: *mem_mod.RealModeMemory,
    cpu: *cpu_mod.CpuState,
    load_segment: u16,
) !LoadedProgram {
    try initPsp(mem, load_segment);
    cpu.cs = load_segment;
    cpu.ds = load_segment;
    cpu.es = load_segment;
    cpu.ss = load_segment;
    cpu.ip = 0x0100;
    cpu.sp = 0xFFFE;
    const loaded: LoadedProgram = .{
        .kind = .source_reference,
        .psp_segment = load_segment,
        .load_segment = load_segment,
        .entry_cs = load_segment,
        .entry_ip = 0x0100,
        .stack_ss = load_segment,
        .stack_sp = 0xFFFE,
    };
    runtime_abi.dos.validateLoad("source_reference", mem.bytes.len, loaded.psp_segment, loaded.load_segment, loaded.entry_cs, loaded.entry_ip, loaded.stack_ss, loaded.stack_sp);
    return loaded;
}

fn parseMzHeader(image: []const u8) !MzHeader {
    if (image.len < 28) return error.InvalidMzImage;
    if (image[0] != 'M' or image[1] != 'Z') return error.InvalidMzSignature;
    return .{
        .bytes_in_last_page = le16(image, 0x02),
        .page_count = le16(image, 0x04),
        .relocation_count = le16(image, 0x06),
        .header_paragraphs = le16(image, 0x08),
        .min_alloc_paragraphs = le16(image, 0x0A),
        .max_alloc_paragraphs = le16(image, 0x0C),
        .initial_ss = le16(image, 0x0E),
        .initial_sp = le16(image, 0x10),
        .checksum = le16(image, 0x12),
        .initial_ip = le16(image, 0x14),
        .initial_cs = le16(image, 0x16),
        .relocation_table_offset = le16(image, 0x18),
        .overlay_number = le16(image, 0x1A),
    };
}

fn imageSize(header: MzHeader, image_len: usize) usize {
    if (header.page_count == 0) return image_len;
    var total = @as(usize, header.page_count) * 512;
    if (header.bytes_in_last_page != 0) total = (total - 512) + header.bytes_in_last_page;
    return @min(total, image_len);
}

pub fn loadMz(
    mem: *mem_mod.RealModeMemory,
    cpu: *cpu_mod.CpuState,
    image: []const u8,
    psp_segment: u16,
) !LoadedProgram {
    const header = try parseMzHeader(image);
    try initPsp(mem, psp_segment);

    const load_segment: u16 = psp_segment + 0x10;
    const body_offset = @as(usize, header.header_paragraphs) * 16;
    if (body_offset > image.len) return error.InvalidMzImage;
    const payload = image[body_offset..imageSize(header, image.len)];
    try mem.writeBytes(load_segment, 0, payload);

    var reloc_off: usize = header.relocation_table_offset;
    var reloc_index: u16 = 0;
    while (reloc_index < header.relocation_count) : (reloc_index += 1) {
        if (reloc_off + 4 > image.len) return error.InvalidMzRelocationTable;
        const offset = le16(image, reloc_off);
        const segment = le16(image, reloc_off + 2);
        const value = try mem.read16(load_segment + segment, offset);
        try mem.write16(load_segment + segment, offset, value +% load_segment);
        reloc_off += 4;
    }

    cpu.cs = load_segment + header.initial_cs;
    cpu.ip = header.initial_ip;
    cpu.ss = load_segment + header.initial_ss;
    cpu.sp = header.initial_sp;
    cpu.ds = psp_segment;
    cpu.es = psp_segment;

    const loaded: LoadedProgram = .{
        .kind = .mz,
        .psp_segment = psp_segment,
        .load_segment = load_segment,
        .entry_cs = cpu.cs,
        .entry_ip = cpu.ip,
        .stack_ss = cpu.ss,
        .stack_sp = cpu.sp,
    };
    runtime_abi.dos.validateMzLoad(mem.bytes.len, load_segment, payload.len, header.relocation_count, header.relocation_table_offset, cpu.cs, cpu.ip, cpu.ss, cpu.sp);
    runtime_abi.dos.validateLoad("mz", mem.bytes.len, loaded.psp_segment, loaded.load_segment, loaded.entry_cs, loaded.entry_ip, loaded.stack_ss, loaded.stack_sp);
    psp_trace.logMzLoad("loadMz", load_segment, cpu.cs, cpu.ip, cpu.ss, cpu.sp);
    return loaded;
}

test "com loader initializes tiny model state" {
    var cpu: cpu_mod.CpuState = .{};
    var mem = try mem_mod.RealModeMemory.initDefault(std.testing.allocator);
    defer mem.deinit();

    const loaded = try loadCom(&mem, &cpu, "ABC", 0x1200);
    try std.testing.expectEqual(ImageKind.com, loaded.kind);
    try std.testing.expectEqual(@as(u16, 0x1200), cpu.cs);
    try std.testing.expectEqual(@as(u16, 0x0100), cpu.ip);
    try std.testing.expectEqual(@as(u8, 'A'), try mem.read8(0x1200, 0x0100));
}

test "psp initialization populates int20 env and command tail defaults" {
    var mem = try mem_mod.RealModeMemory.initDefault(std.testing.allocator);
    defer mem.deinit();

    try initPsp(&mem, 0x2345);
    try std.testing.expectEqual(@as(u8, 0xCD), try mem.read8(0x2345, 0x0000));
    try std.testing.expectEqual(@as(u8, 0x20), try mem.read8(0x2345, 0x0001));
    try std.testing.expectEqual(@as(u16, 0x2365), try mem.read16(0x2345, 0x002C));
    try std.testing.expectEqual(@as(u8, 0), try mem.read8(0x2345, 0x0080));
    try std.testing.expectEqual(@as(u8, 0x0D), try mem.read8(0x2345, 0x0081));
}

test "mz loader handles tiny executable with no relocations" {
    var cpu: cpu_mod.CpuState = .{};
    var mem = try mem_mod.RealModeMemory.initDefault(std.testing.allocator);
    defer mem.deinit();

    const image = [_]u8{
        'M', 'Z', 0x22, 0x00, 0x01, 0x00, 0x00, 0x00,
        0x02, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0x00, 0x00,
        0x00, 0x80, 0x00, 0x00, 0x34, 0x12, 0x00, 0x00,
        0x1C, 0x00, 0x00, 0x00, 0x90, 0xC3, 0x00, 0x00,
        0x90, 0xC3,
    };

    const loaded = try loadMz(&mem, &cpu, &image, 0x1400);
    try std.testing.expectEqual(ImageKind.mz, loaded.kind);
    try std.testing.expectEqual(@as(u16, 0x1410), loaded.load_segment);
    try std.testing.expectEqual(@as(u16, 0x1410), cpu.cs);
    try std.testing.expectEqual(@as(u16, 0x1234), cpu.ip);
    try std.testing.expectEqual(@as(u16, 0x1410), cpu.ss);
    try std.testing.expectEqual(@as(u16, 0x8000), cpu.sp);
    try std.testing.expectEqual(@as(u8, 0x90), try mem.read8(0x1410, 0x0000));
    try std.testing.expectEqual(@as(u8, 0xC3), try mem.read8(0x1410, 0x0001));
}
