const std = @import("std");

const HEADER_SIZE: usize = 28;
const INDEX_ENTRY_SIZE: usize = 12;
const LSDA_ENTRY_SIZE: usize = 8;
const REGULAR_SECOND_LEVEL: u32 = 2;
const COMPRESSED_SECOND_LEVEL: u32 = 3;
const MODE_MASK: u32 = 0x0F00_0000;
const HAS_LSDA: u32 = 0x4000_0000;

pub const Mode = enum {
    rbp_frame,
    stack_immediate,
    stack_indirect,
    dwarf,
    unknown,
};

pub const FrameInfo = struct {
    function_start: u64,
    function_end: u64,
    encoding: u32,
    mode: Mode,
    lsda_address: u64 = 0,
    personality_address: u64 = 0,
};

pub const Index = struct {
    data: []const u8,
    section_address: u64,
    image_base: u64,

    pub fn init(data: []const u8, section_address: u64, image_base: u64) ?Index {
        if (data.len < HEADER_SIZE or read32(data, 0) != 1) return null;
        return .{ .data = data, .section_address = section_address, .image_base = image_base };
    }

    pub fn lookup(self: *const Index, address: u64) ?FrameInfo {
        if (address < self.image_base) return null;
        const target: u32 = @intCast(@min(address - self.image_base, std.math.maxInt(u32)));
        const common_offset = read32(self.data, 4);
        const common_count = read32(self.data, 8);
        const personality_offset = read32(self.data, 12);
        const personality_count = read32(self.data, 16);
        const index_offset = read32(self.data, 20);
        const index_count = read32(self.data, 24);
        if (index_count < 2) return null;

        var top_index: usize = 0;
        while (top_index + 1 < index_count) : (top_index += 1) {
            const current = indexEntry(self.data, index_offset, top_index) orelse return null;
            const next = indexEntry(self.data, index_offset, top_index + 1) orelse return null;
            if (target < current.function_offset or target >= next.function_offset) continue;
            const encoded = self.lookupSecondLevel(current, next, target, common_offset, common_count) orelse return null;
            const lsda = if ((encoded.encoding & HAS_LSDA) != 0)
                self.lookupLsda(current, next, encoded.function_offset)
            else
                0;
            const personality_index = (encoded.encoding >> 28) & 0x3;
            var personality: u64 = 0;
            if (personality_index != 0 and personality_index <= personality_count) {
                const slot = @as(usize, personality_offset) + (@as(usize, personality_index) - 1) * 4;
                if (slot + 4 <= self.data.len) personality = self.image_base + read32(self.data, slot);
            }
            return .{
                .function_start = self.image_base + encoded.function_offset,
                .function_end = self.image_base + encoded.function_end,
                .encoding = encoded.encoding,
                .mode = modeFor(encoded.encoding),
                .lsda_address = if (lsda == 0) 0 else self.image_base + lsda,
                .personality_address = personality,
            };
        }
        return null;
    }

    const TopEntry = struct {
        function_offset: u32,
        page_offset: u32,
        lsda_offset: u32,
    };

    const EncodedEntry = struct {
        function_offset: u32,
        function_end: u32,
        encoding: u32,
    };

    fn lookupSecondLevel(
        self: *const Index,
        current: TopEntry,
        next: TopEntry,
        target: u32,
        common_offset: u32,
        common_count: u32,
    ) ?EncodedEntry {
        const page = @as(usize, current.page_offset);
        if (page + 8 > self.data.len) return null;
        return switch (read32(self.data, page)) {
            REGULAR_SECOND_LEVEL => self.lookupRegular(page, next.function_offset, target),
            COMPRESSED_SECOND_LEVEL => self.lookupCompressed(page, current.function_offset, next.function_offset, target, common_offset, common_count),
            else => null,
        };
    }

    fn lookupRegular(self: *const Index, page: usize, page_end: u32, target: u32) ?EncodedEntry {
        const entries_offset = read16(self.data, page + 4);
        const count = read16(self.data, page + 6);
        var best: ?EncodedEntry = null;
        for (0..count) |entry_index| {
            const offset = page + entries_offset + entry_index * 8;
            if (offset + 8 > self.data.len) return null;
            const function_offset = read32(self.data, offset);
            const function_end = if (entry_index + 1 < count) read32(self.data, offset + 8) else page_end;
            if (target >= function_offset and target < function_end) {
                best = .{ .function_offset = function_offset, .function_end = function_end, .encoding = read32(self.data, offset + 4) };
                break;
            }
        }
        return best;
    }

    fn lookupCompressed(
        self: *const Index,
        page: usize,
        page_start: u32,
        page_end: u32,
        target: u32,
        common_offset: u32,
        common_count: u32,
    ) ?EncodedEntry {
        if (page + 12 > self.data.len) return null;
        const entries_offset = read16(self.data, page + 4);
        const count = read16(self.data, page + 6);
        const local_offset = read16(self.data, page + 8);
        const local_count = read16(self.data, page + 10);
        _ = local_count;
        for (0..count) |entry_index| {
            const offset = page + entries_offset + entry_index * 4;
            if (offset + 4 > self.data.len) return null;
            const packed_entry = read32(self.data, offset);
            const function_offset = page_start + (packed_entry & 0x00FF_FFFF);
            const function_end = if (entry_index + 1 < count)
                page_start + (read32(self.data, offset + 4) & 0x00FF_FFFF)
            else
                page_end;
            if (target < function_offset or target >= function_end) continue;
            const encoding_index = packed_entry >> 24;
            const encoding_offset = if (encoding_index < common_count)
                @as(usize, common_offset) + @as(usize, encoding_index) * 4
            else
                page + local_offset + (@as(usize, encoding_index) - common_count) * 4;
            if (encoding_offset + 4 > self.data.len) return null;
            return .{ .function_offset = function_offset, .function_end = function_end, .encoding = read32(self.data, encoding_offset) };
        }
        return null;
    }

    fn lookupLsda(self: *const Index, current: TopEntry, next: TopEntry, function_offset: u32) u32 {
        var offset = @as(usize, current.lsda_offset);
        const end = @min(@as(usize, next.lsda_offset), self.data.len);
        while (offset + LSDA_ENTRY_SIZE <= end) : (offset += LSDA_ENTRY_SIZE) {
            const function = read32(self.data, offset);
            if (function == function_offset) return read32(self.data, offset + 4);
            if (function > function_offset) break;
        }
        return 0;
    }
};

fn indexEntry(data: []const u8, index_offset: u32, index: usize) ?Index.TopEntry {
    const offset = @as(usize, index_offset) + index * INDEX_ENTRY_SIZE;
    if (offset + INDEX_ENTRY_SIZE > data.len) return null;
    return .{
        .function_offset = read32(data, offset),
        .page_offset = read32(data, offset + 4),
        .lsda_offset = read32(data, offset + 8),
    };
}

fn modeFor(encoding: u32) Mode {
    return switch (encoding & MODE_MASK) {
        0x0100_0000 => .rbp_frame,
        0x0200_0000 => .stack_immediate,
        0x0300_0000 => .stack_indirect,
        0x0400_0000 => .dwarf,
        else => .unknown,
    };
}

fn read16(data: []const u8, offset: usize) u16 {
    if (offset + 2 > data.len) return 0;
    return std.mem.readInt(u16, data[offset..][0..2], .little);
}

fn read32(data: []const u8, offset: usize) u32 {
    if (offset + 4 > data.len) return 0;
    return std.mem.readInt(u32, data[offset..][0..4], .little);
}

test "regular second-level page resolves function and LSDA" {
    var data = [_]u8{0} ** 160;
    std.mem.writeInt(u32, data[0..4], 1, .little);
    std.mem.writeInt(u32, data[20..24], 32, .little);
    std.mem.writeInt(u32, data[24..28], 2, .little);
    std.mem.writeInt(u32, data[32..36], 0x100, .little);
    std.mem.writeInt(u32, data[36..40], 64, .little);
    std.mem.writeInt(u32, data[40..44], 96, .little);
    std.mem.writeInt(u32, data[44..48], 0x200, .little);
    std.mem.writeInt(u32, data[52..56], 104, .little);
    std.mem.writeInt(u32, data[64..68], REGULAR_SECOND_LEVEL, .little);
    std.mem.writeInt(u16, data[68..70], 8, .little);
    std.mem.writeInt(u16, data[70..72], 1, .little);
    std.mem.writeInt(u32, data[72..76], 0x100, .little);
    std.mem.writeInt(u32, data[76..80], 0x4100_0000, .little);
    std.mem.writeInt(u32, data[96..100], 0x100, .little);
    std.mem.writeInt(u32, data[100..104], 0x300, .little);

    const index = Index.init(&data, 0x5000, 0x1000).?;
    const frame = index.lookup(0x1110).?;
    try std.testing.expectEqual(@as(u64, 0x1100), frame.function_start);
    try std.testing.expectEqual(Mode.rbp_frame, frame.mode);
    try std.testing.expectEqual(@as(u64, 0x1300), frame.lsda_address);
}
