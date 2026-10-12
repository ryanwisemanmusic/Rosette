//! Auxiliary exact-address index for the append-only Windows guest heap
//! provenance table. Records remain in guest-address order for the fallback
//! binary search and diagnostics; this table only accelerates exact lookups.

const std = @import("std");

pub const Lookup = struct {
    index: ?usize,
    probes: usize,
};

pub const AppendResult = enum { indexed, failed, disabled };

pub fn requiredSlots(record_count: usize) ?usize {
    const minimum = std.math.mul(usize, record_count, 2) catch return null;
    var capacity: usize = 16;
    while (capacity < minimum) {
        capacity = std.math.mul(usize, capacity, 2) catch return null;
    }
    return capacity;
}

pub fn rebuild(slots: []u32, records: anytype) bool {
    if (slots.len == 0 or !std.math.isPowerOfTwo(slots.len)) return false;
    if (records.len > slots.len / 2) return false;
    @memset(slots, 0);
    for (records, 0..) |_, index| {
        if (!insert(slots, records, index)) return false;
    }
    return true;
}

/// Append one newly recorded base address, growing and rebuilding the table
/// geometrically. Failure disables only the accelerator; the ordered record
/// table remains authoritative and callers continue with binary search.
pub fn appendRecord(
    allocator: std.mem.Allocator,
    slots: *[]u32,
    indexed_records: *usize,
    disabled: *bool,
    records: anytype,
    index: usize,
) AppendResult {
    if (disabled.*) return .disabled;
    if (index != indexed_records.* or index >= records.len) {
        disabled.* = true;
        return .failed;
    }
    const required = requiredSlots(index + 1) orelse {
        disabled.* = true;
        return .failed;
    };
    if (required > slots.len) {
        const grown = allocator.alloc(u32, required) catch {
            disabled.* = true;
            return .failed;
        };
        @memset(grown, 0);
        if (!rebuild(grown, records[0 .. index + 1])) {
            allocator.free(grown);
            disabled.* = true;
            return .failed;
        }
        if (slots.len != 0) allocator.free(slots.*);
        slots.* = grown;
    } else if (!insert(slots.*, records, index)) {
        disabled.* = true;
        return .failed;
    }
    indexed_records.* = index + 1;
    return .indexed;
}

pub fn insert(slots: []u32, records: anytype, index: usize) bool {
    if (slots.len == 0 or !std.math.isPowerOfTwo(slots.len) or index >= records.len) return false;
    const encoded_index = std.math.cast(u32, index + 1) orelse return false;
    const mask = slots.len - 1;
    var slot: usize = @intCast(hash(records[index].guest_base) & @as(u64, @intCast(mask)));
    for (0..slots.len) |_| {
        const entry = slots[slot];
        if (entry == 0) {
            slots[slot] = encoded_index;
            return true;
        }
        const existing: usize = entry - 1;
        if (existing >= records.len) return false;
        if (records[existing].guest_base == records[index].guest_base) return existing == index;
        slot = (slot + 1) & mask;
    }
    return false;
}

pub fn lookup(slots: []const u32, records: anytype, guest_base: u64) Lookup {
    if (slots.len == 0 or !std.math.isPowerOfTwo(slots.len)) return .{ .index = null, .probes = 0 };
    const mask = slots.len - 1;
    var slot: usize = @intCast(hash(guest_base) & @as(u64, @intCast(mask)));
    var probes: usize = 0;
    while (probes < slots.len) : (probes += 1) {
        const entry = slots[slot];
        if (entry == 0) return .{ .index = null, .probes = probes + 1 };
        const index: usize = entry - 1;
        if (index < records.len and records[index].guest_base == guest_base) {
            return .{ .index = index, .probes = probes + 1 };
        }
        slot = (slot + 1) & mask;
    }
    return .{ .index = null, .probes = probes };
}

fn hash(key: u64) u64 {
    var mixed = key;
    mixed ^= mixed >> 30;
    mixed *%= 0xbf58476d1ce4e5b9;
    mixed ^= mixed >> 27;
    mixed *%= 0x94d049bb133111eb;
    mixed ^= mixed >> 31;
    return mixed;
}

test "exact heap address index resolves sorted records through growth and collisions" {
    const Record = struct { guest_base: u64 };
    var records: [4096]Record = undefined;
    for (&records, 0..) |*record, index| {
        // A fixed stride makes the source sorted while the mixed hash creates
        // collisions that must be followed through the linear-probe chain.
        record.guest_base = 0x1000_0000 + @as(u64, @intCast(index)) * 0x30;
    }
    var slots: [8192]u32 = @splat(0);
    try std.testing.expect(rebuild(&slots, &records));
    for (&records, 0..) |record, expected| {
        const found = lookup(&slots, &records, record.guest_base);
        try std.testing.expectEqual(@as(?usize, expected), found.index);
        try std.testing.expect(found.probes > 0 and found.probes < slots.len);
    }
    try std.testing.expect(lookup(&slots, &records, 0xFFFF_FFFF).index == null);
    try std.testing.expectEqual(@as(?usize, 32), requiredSlots(9));
    try std.testing.expectEqual(@as(?usize, 8192), requiredSlots(records.len));
}

test "index refuses duplicate keys that name different provenance records" {
    const Record = struct { guest_base: u64 };
    const records = [_]Record{ .{ .guest_base = 0x1000 }, .{ .guest_base = 0x1000 } };
    var slots: [16]u32 = @splat(0);
    try std.testing.expect(insert(&slots, &records, 0));
    try std.testing.expect(!insert(&slots, &records, 1));
    try std.testing.expectEqual(@as(?usize, 0), lookup(&slots, &records, 0x1000).index);
}
