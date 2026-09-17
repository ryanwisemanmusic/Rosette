//! Sorted, disjoint Windows mappings. Mutations happen at map/unmap, not at
//! each guest load/store. Entries contain table indexes, never borrowed host
//! pointers, so release/reuse cannot retain a dangling backing allocation.
const std = @import("std");

pub const Kind = enum { memory_view, virtual_allocation };
pub const Range = struct { base: u64, length: u64, kind: Kind, slot: usize };
pub const capacity = 128; // 64 views + 64 fixed allocations.
pub const Index = struct {
    ranges: [capacity]Range = undefined,
    count: usize = 0,
    mutations: u64 = 0,

    pub fn insert(self: *Index, range: Range) bool {
        if (range.length == 0 or self.count == capacity) return false;
        const end = std.math.add(u64, range.base, range.length) catch return false;
        var position: usize = 0;
        while (position < self.count and self.ranges[position].base < range.base) : (position += 1) {}
        if (position != 0) {
            const previous = self.ranges[position - 1];
            if (previous.base + previous.length > range.base) return false;
        }
        if (position < self.count and end > self.ranges[position].base) return false;
        var cursor = self.count;
        while (cursor > position) : (cursor -= 1) self.ranges[cursor] = self.ranges[cursor - 1];
        self.ranges[position] = range;
        self.count += 1;
        self.mutations +|= 1;
        return true;
    }

    pub fn remove(self: *Index, kind: Kind, slot: usize) void {
        for (self.ranges[0..self.count], 0..) |range, position| {
            if (range.kind != kind or range.slot != slot) continue;
            var cursor = position;
            while (cursor + 1 < self.count) : (cursor += 1) self.ranges[cursor] = self.ranges[cursor + 1];
            self.count -= 1;
            self.mutations +|= 1;
            return;
        }
    }

    /// At most eight base comparisons at the full 128-entry capacity. A span
    /// crossing a mapping boundary never borrows bytes from the next range.
    pub fn find(self: *const Index, address: u64, length: u64) ?Range {
        const end = std.math.add(u64, address, length) catch return null;
        var low: usize = 0;
        var high = self.count;
        while (low < high) {
            const middle = low + (high - low) / 2;
            if (self.ranges[middle].base <= address) low = middle + 1 else high = middle;
        }
        if (low == 0) return null;
        const candidate = self.ranges[low - 1];
        if (address - candidate.base >= candidate.length or end > candidate.base + candidate.length) return null;
        return candidate;
    }
};

test "mapped range index is sorted, exact, nonoverlapping and overflow safe" {
    var index: Index = .{};
    try std.testing.expect(index.insert(.{ .base = 0x3000, .length = 0x1000, .kind = .memory_view, .slot = 3 }));
    try std.testing.expect(index.insert(.{ .base = 0x1000, .length = 0x1000, .kind = .virtual_allocation, .slot = 1 }));
    try std.testing.expect(index.insert(.{ .base = 0x2000, .length = 0x1000, .kind = .memory_view, .slot = 2 }));
    try std.testing.expectEqual(@as(usize, 1), index.find(0x1ffc, 4).?.slot);
    try std.testing.expectEqual(@as(usize, 2), index.find(0x2000, 1).?.slot);
    try std.testing.expect(index.find(0x1ffc, 5) == null);
    try std.testing.expect(index.find(0x4000, 1) == null);
    try std.testing.expect(index.find(std.math.maxInt(u64), 2) == null);
    try std.testing.expect(!index.insert(.{ .base = 0x1fff, .length = 2, .kind = .memory_view, .slot = 9 }));
    try std.testing.expect(!index.insert(.{ .base = std.math.maxInt(u64), .length = 2, .kind = .memory_view, .slot = 9 }));
    index.remove(.memory_view, 2);
    try std.testing.expect(index.find(0x2000, 1) == null);
    try std.testing.expect(index.insert(.{ .base = 0x2000, .length = 0x100, .kind = .virtual_allocation, .slot = 2 }));
    try std.testing.expectEqual(Kind.virtual_allocation, index.find(0x2000, 1).?.kind);
    try std.testing.expect(index.find(0x2100, 1) == null);
}

test "mapped range index covers every slot at capacity and survives removal and reuse" {
    var index: Index = .{};
    for (0..capacity) |slot| try std.testing.expect(index.insert(.{
        .base = @as(u64, @intCast(capacity - slot)) * 0x10000,
        .length = 0x1000,
        .kind = if (slot < 64) .memory_view else .virtual_allocation,
        .slot = slot % 64,
    }));
    for (index.ranges) |range| try std.testing.expectEqual(range, index.find(range.base + 0xfff, 1).?);
    try std.testing.expect(!index.insert(.{ .base = 0, .length = 1, .kind = .memory_view, .slot = 64 }));
    for (0..64) |slot| index.remove(.memory_view, slot);
    try std.testing.expectEqual(@as(usize, 64), index.count);
    for (index.ranges[0..index.count]) |range| try std.testing.expectEqual(Kind.virtual_allocation, range.kind);
}
