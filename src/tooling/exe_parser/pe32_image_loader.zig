//! Map one preferred-base PE32 image into an executor's flat guest address
//! range. This is shared by the top-level PE32 runner and its child-process
//! loader; it deliberately does not resolve imports or emulate relocations.
const std = @import("std");
const parser = @import("pe_parser.zig");
const code_text = @import("entrypoint_code_text_segment");
const Executor = @import("x86_asm").instruction_operations.Executor;

pub const MappedImage = struct {
    base: u32,
    entry: u32,
    size: u32,
};

pub const MapError = error{
    NotPe32I386,
    PreferredBaseMismatch,
    ImageRangeOverflow,
    ImageOutOfMemory,
    HeaderOutOfRange,
    SectionOutOfRange,
};

/// Copy headers and sections into the executor at the image's preferred base.
/// The caller owns import resolution and process startup state. Relocated
/// images are rejected until a relocation-table loader is implemented.
pub fn mapPreferredBase(exec: *Executor, bytes: []const u8, image: *const parser.Image, base: u32) MapError!MappedImage {
    if (image.isPe32Plus() or image.machine != 0x014C) return error.NotPe32I386;
    const preferred_base = std.math.cast(u32, image.image_base) orelse return error.ImageRangeOverflow;
    if (base != preferred_base) return error.PreferredBaseMismatch;
    if (base < exec.mem.base) return error.ImageOutOfMemory;
    const end = std.math.add(u64, @as(u64, base), image.size_of_image) catch return error.ImageRangeOverflow;
    const mem_end = std.math.add(u64, @as(u64, exec.mem.base), exec.mem.data.len) catch return error.ImageRangeOverflow;
    if (end > mem_end or end > @as(u64, std.math.maxInt(u32)) + 1) return error.ImageOutOfMemory;

    const image_offset: usize = @intCast(base - exec.mem.base);
    const image_len: usize = @intCast(image.size_of_image);
    @memset(exec.mem.data[image_offset .. image_offset + image_len], 0);

    const header_len: usize = @intCast(image.size_of_headers);
    if (header_len > bytes.len or header_len > image_len) return error.HeaderOutOfRange;
    @memcpy(exec.mem.data[image_offset .. image_offset + header_len], bytes[0..header_len]);

    for (image.sections) |section| {
        const mapped_size = section.mappedSize();
        const section_end = std.math.add(u64, section.virtual_address, mapped_size) catch return error.SectionOutOfRange;
        if (section_end > image.size_of_image) return error.SectionOutOfRange;
        if (section.raw_size != 0) {
            const raw_start: usize = @intCast(section.raw_offset);
            const raw_size: usize = @intCast(section.raw_size);
            if (raw_start > bytes.len or raw_size > bytes.len - raw_start) return error.SectionOutOfRange;
            const rva_start: usize = @intCast(section.virtual_address);
            if (rva_start > image_len or raw_size > image_len - rva_start) return error.SectionOutOfRange;
            const dest_start = image_offset + rva_start;
            @memcpy(exec.mem.data[dest_start .. dest_start + raw_size], bytes[raw_start .. raw_start + raw_size]);
        }

        if (mapped_size != 0) {
            exec.addCodeTextSegment(code_text.Segment.init(
                base + section.virtual_address,
                mapped_size,
                section.isExecutable(),
                std.mem.sliceTo(&section.name, 0),
            ));
        }
    }

    // For a child process, the backing range may include several images and a
    // reserved guest heap. Segments keep instruction fetches restricted to
    // executable PE sections while this outer range admits every mapped VA.
    const backing_span: u32 = @intCast(exec.mem.data.len);
    exec.setLoadedImageSize(backing_span);
    return .{
        .base = base,
        .entry = std.math.add(u32, base, image.entry_rva) catch return error.ImageRangeOverflow,
        .size = image.size_of_image,
    };
}

fn writeU16(bytes: []u8, offset: usize, value: u16) void {
    std.mem.writeInt(u16, bytes[offset..][0..2], value, .little);
}

fn writeU32(bytes: []u8, offset: usize, value: u32) void {
    std.mem.writeInt(u32, bytes[offset..][0..4], value, .little);
}

fn minimalPe32(allocator: std.mem.Allocator) ![]u8 {
    const bytes = try allocator.alloc(u8, 0x600);
    @memset(bytes, 0);
    writeU16(bytes, 0, 0x5A4D);
    writeU32(bytes, 0x3C, 0x80);
    writeU32(bytes, 0x80, 0x00004550);
    writeU16(bytes, 0x84, 0x014C);
    writeU16(bytes, 0x86, 1);
    writeU16(bytes, 0x94, 0xE0);
    writeU16(bytes, 0x98, 0x010B);
    writeU32(bytes, 0xA8, 0x1234);
    writeU32(bytes, 0xB4, 0x00400000);
    writeU32(bytes, 0xB8, 0x1000);
    writeU32(bytes, 0xBC, 0x200);
    writeU32(bytes, 0xD0, 0x5000);
    writeU32(bytes, 0xD4, 0x400);
    writeU16(bytes, 0xDC, 2);
    @memcpy(bytes[0x178..0x180], ".text\x00\x00\x00");
    writeU32(bytes, 0x180, 0x1000);
    writeU32(bytes, 0x184, 0x1000);
    writeU32(bytes, 0x188, 0x200);
    writeU32(bytes, 0x18C, 0x400);
    writeU32(bytes, 0x19C, 0x60000020);
    bytes[0x400] = 0x90;
    bytes[0x401] = 0xC3;
    return bytes;
}

test "PE32 preferred-base mapper copies headers, maps sections, and guards code" {
    const bytes = try minimalPe32(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    const image = try parser.parse(std.testing.allocator, bytes);
    defer std.testing.allocator.free(image.sections);

    var exec = Executor.init(std.testing.allocator, 0x20000);
    defer exec.deinit();
    exec.mem.base = 0x00400000;
    const mapped = try mapPreferredBase(&exec, bytes, &image, 0x00400000);

    try std.testing.expectEqual(@as(u32, 0x00401234), mapped.entry);
    try std.testing.expectEqual(@as(u8, 0x5A), exec.mem.data[0]);
    try std.testing.expectEqual(@as(u8, 0x90), exec.mem.data[0x1000]);
    try std.testing.expectEqual(@as(u8, 0xC3), exec.mem.data[0x1001]);
    try std.testing.expectEqual(@as(u8, 0), exec.mem.data[0x1200]);
    try std.testing.expect(exec.codeTextGuard().segments[0].containsAddress(0x00401000));
    try std.testing.expect(!exec.codeTextGuard().segments[0].containsAddress(0x00402000));
}

test "PE32 preferred-base mapper rejects a nonmatching allocation base" {
    const bytes = try minimalPe32(std.testing.allocator);
    defer std.testing.allocator.free(bytes);
    const image = try parser.parse(std.testing.allocator, bytes);
    defer std.testing.allocator.free(image.sections);

    var exec = Executor.init(std.testing.allocator, 0x20000);
    defer exec.deinit();
    exec.mem.base = 0x00500000;
    try std.testing.expectError(error.PreferredBaseMismatch, mapPreferredBase(&exec, bytes, &image, 0x00500000));
}
