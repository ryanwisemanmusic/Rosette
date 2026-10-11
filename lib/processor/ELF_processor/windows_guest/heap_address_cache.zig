//! Thread-local exact-address cache for the PE heap's ordered provenance map.
//!
//! Allocation records are append-only and remain sorted by guest base, so a
//! cached index remains meaningful for the lifetime of the record. Every hit
//! is still checked against the current table before it is returned; this is
//! important when an ElfState address is reused or the record array grows.

const std = @import("std");

pub const capacity: usize = 1024;

pub const Record = struct { guest_base: u64 };

const Entry = struct {
    valid: bool = false,
    guest_base: u64 = 0,
    record_index: usize = 0,
};

const State = struct {
    owner: ?*anyopaque = null,
    entries: [capacity]Entry = @splat(.{}),
};

threadlocal var state: State = .{};

fn indexFor(guest_base: u64) usize {
    const mixed = guest_base *% 0x9E3779B97F4A7C15;
    return @intCast((mixed ^ (mixed >> 32)) & (capacity - 1));
}

/// Return an exact cached record index, validating it against the live table.
pub fn lookup(owner: *anyopaque, guest_base: u64, records: anytype) ?usize {
    if (state.owner != owner) {
        state.owner = owner;
        @memset(&state.entries, .{});
        return null;
    }
    const entry = state.entries[indexFor(guest_base)];
    if (!entry.valid or entry.guest_base != guest_base or entry.record_index >= records.len) return null;
    if (records[entry.record_index].guest_base != guest_base) return null;
    return entry.record_index;
}

pub fn remember(owner: *anyopaque, guest_base: u64, record_index: usize) void {
    if (state.owner != owner) {
        state.owner = owner;
        @memset(&state.entries, .{});
    }
    state.entries[indexFor(guest_base)] = .{
        .valid = true,
        .guest_base = guest_base,
        .record_index = record_index,
    };
}

test "heap address cache validates hits, append-only indexes, and owner changes" {
    var first_owner: u8 = 0;
    var second_owner: u8 = 0;
    var records = [_]Record{ .{ .guest_base = 0x1000 }, .{ .guest_base = 0x3000 } };

    try std.testing.expect(lookup(&first_owner, 0x1000, &records) == null);
    remember(&first_owner, 0x1000, 0);
    try std.testing.expectEqual(@as(?usize, 0), lookup(&first_owner, 0x1000, &records));

    // Reallocation can move the slice; the stable record index still works.
    records = .{ .{ .guest_base = 0x1000 }, .{ .guest_base = 0x3000 } };
    try std.testing.expectEqual(@as(?usize, 0), lookup(&first_owner, 0x1000, &records));

    // A stale or corrupt index cannot resolve a different allocation.
    remember(&first_owner, 0x3000, 0);
    try std.testing.expect(lookup(&first_owner, 0x3000, &records) == null);

    remember(&second_owner, 0x3000, 1);
    try std.testing.expectEqual(@as(?usize, 1), lookup(&second_owner, 0x3000, &records));
    try std.testing.expect(lookup(&first_owner, 0x3000, &records) == null);
}
