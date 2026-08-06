//! One definition of bounded-ring index arithmetic.
//!
//! Before this existed, seven files each re-derived the same three expressions:
//! `if (filled) LEN else index` for the count, `(index + ordinal) % LEN` for
//! chronological access, and `if (index == 0) LEN - 1 else index - 1` for the
//! most recent entry. They were written out by hand in `near_null_causality`,
//! `memory_access`, `diagnostics`, `crash_diag`, `import-handler/dispatch`,
//! `Mach-O/process` and `ELF_processor/process`. Seven copies of an
//! off-by-one-prone expression is seven chances to disagree about what "the
//! oldest retained entry" means — and they are consulted by code that decides
//! whether to redirect control flow.

const std = @import("std");

/// A bounded ring over a caller-provided slice. The slice is owned by the
/// caller (usually one contiguous allocation partitioned across several rings),
/// so this type is a view plus a cursor and copies cheaply.
pub fn Ring(comptime T: type) type {
    return struct {
        const Self = @This();

        entries: []T,
        index: usize = 0,
        filled: bool = false,

        pub fn init(entries: []T) Self {
            return .{ .entries = entries };
        }

        pub fn capacity(self: Self) usize {
            return self.entries.len;
        }

        /// Retained entries, never more than capacity.
        pub fn count(self: Self) usize {
            return if (self.filled) self.entries.len else self.index;
        }

        pub fn isEmpty(self: Self) bool {
            return self.count() == 0;
        }

        pub fn push(self: *Self, value: T) void {
            if (self.entries.len == 0) return;
            self.entries[self.index] = value;
            self.index += 1;
            if (self.index == self.entries.len) {
                self.index = 0;
                self.filled = true;
            }
        }

        /// Chronological access: ordinal 0 is the oldest retained entry,
        /// `count() - 1` the newest. Returns null when out of range, so callers
        /// cannot silently read an unwritten slot.
        pub fn chronological(self: Self, ordinal: usize) ?T {
            const n = self.count();
            if (ordinal >= n) return null;
            const start: usize = if (self.filled) self.index else 0;
            return self.entries[(start + ordinal) % self.entries.len];
        }

        /// Reverse-chronological access: 0 is the newest retained entry.
        pub fn recent(self: Self, ordinal: usize) ?T {
            const n = self.count();
            if (ordinal >= n) return null;
            return self.chronological(n - 1 - ordinal);
        }

        pub fn latest(self: Self) ?T {
            return self.recent(0);
        }

        pub fn reset(self: *Self) void {
            self.index = 0;
            self.filled = false;
        }
    };
}

test "chronological order is oldest-first and survives wraparound" {
    var storage: [4]u32 = undefined;
    var ring = Ring(u32).init(&storage);
    try std.testing.expect(ring.isEmpty());
    for ([_]u32{ 1, 2, 3 }) |v| ring.push(v);
    try std.testing.expectEqual(@as(usize, 3), ring.count());
    try std.testing.expectEqual(@as(u32, 1), ring.chronological(0).?);
    try std.testing.expectEqual(@as(u32, 3), ring.chronological(2).?);
    try std.testing.expectEqual(@as(?u32, null), ring.chronological(3));
    try std.testing.expectEqual(@as(u32, 3), ring.latest().?);

    // Wrap: 5,6 evict 1,2 — oldest retained becomes 3.
    for ([_]u32{ 4, 5, 6 }) |v| ring.push(v);
    try std.testing.expectEqual(@as(usize, 4), ring.count());
    try std.testing.expectEqual(@as(u32, 3), ring.chronological(0).?);
    try std.testing.expectEqual(@as(u32, 6), ring.chronological(3).?);
    try std.testing.expectEqual(@as(u32, 6), ring.latest().?);
    try std.testing.expectEqual(@as(u32, 5), ring.recent(1).?);
}

test "an empty backing slice never writes or reads" {
    var storage: [0]u32 = undefined;
    var ring = Ring(u32).init(&storage);
    ring.push(7);
    try std.testing.expectEqual(@as(usize, 0), ring.count());
    try std.testing.expectEqual(@as(?u32, null), ring.latest());
}

test "exactly-full ring reports capacity, not zero" {
    // The hand-written form `if (index == 0) LEN - 1 else index - 1` for the
    // latest entry is correct only when paired with the `filled` flag; getting
    // that pairing wrong reads an unwritten slot on an exactly-full ring.
    var storage: [2]u32 = undefined;
    var ring = Ring(u32).init(&storage);
    ring.push(10);
    ring.push(20);
    try std.testing.expectEqual(@as(usize, 2), ring.count());
    try std.testing.expect(ring.filled);
    try std.testing.expectEqual(@as(usize, 0), ring.index);
    try std.testing.expectEqual(@as(u32, 20), ring.latest().?);
    try std.testing.expectEqual(@as(u32, 10), ring.chronological(0).?);
}
