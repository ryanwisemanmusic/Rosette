//! An exact index from a synthetic Vulkan handle to the slot it occupies in
//! one of the forwarder's fixed provenance tables.
//!
//! The tables themselves stay where they are: fixed arrays of records keyed
//! by `synthetic`, with zero meaning an empty slot. What this replaces is the
//! way they were searched. Every lookup scanned the whole table, and an
//! insert scanned it twice - once for the handle, once for a hole - so a full
//! table charged two complete scans to every update of a handle it could not
//! hold. The 2026-09-22 Halo 3 run spent 80 of its 154 seconds of Vulkan host
//! time in `vkUpdateDescriptorSets` for that reason: 4,096 descriptor-set
//! records of about 410 bytes each, full for most of the run, 10.3 million
//! overflowed updates.
//!
//! The index keeps its own copy of each key, so probing never touches the
//! large records. It uses linear probing with backward-shift deletion, so it
//! never accumulates tombstones however much the tables churn, and it hands
//! out slots from a free list, so a full table is refused in O(1).
//!
//! The index is authoritative: a table indexed by it must be written only
//! through `insert` and `remove` (and cleared with `reset`), or a lookup will
//! answer from a key the table no longer holds. Records it hands out start
//! at slot 0 and stay below `highWater()`, which bounds any caller that still
//! needs to visit every record.

const std = @import("std");

pub fn SlotIndex(comptime capacity: usize) type {
    std.debug.assert(capacity > 0 and capacity <= std.math.maxInt(u16));
    // At most half full, so an unsuccessful probe stays short.
    const bucket_bits: std.math.Log2Int(u64) = @intCast(std.math.log2_int_ceil(usize, capacity * 2));
    const bucket_count: usize = @as(usize, 1) << bucket_bits;
    const mask: usize = bucket_count - 1;

    return struct {
        const Self = @This();

        /// The handle each bucket holds; zero is an empty bucket, which is
        /// why a zero handle is never indexed.
        keys: [bucket_count]u64 = @splat(0),
        /// The table slot of the handle in the same bucket.
        slots: [bucket_count]u16 = @splat(0),
        /// Slots `remove` gave back, reused before new ones.
        free: [capacity]u16 = @splat(0),
        free_len: usize = 0,
        /// Slots below this have been handed out at least once.
        high_water: usize = 0,
        len: usize = 0,

        pub const slot_capacity = capacity;

        fn home(key: u64) usize {
            return @intCast((key *% 0x9E37_79B9_7F4A_7C15) >> @intCast(64 - @as(u7, bucket_bits)));
        }

        /// The slot holding `key`, or null.
        pub fn find(self: *const Self, key: u64) ?usize {
            if (key == 0) return null;
            var bucket = home(key);
            while (true) : (bucket = (bucket + 1) & mask) {
                const held = self.keys[bucket];
                if (held == key) return self.slots[bucket];
                if (held == 0) return null;
            }
        }

        /// Give `key` a slot. `key` must not already be indexed; callers
        /// that are not sure ask `find` first. Null when every slot is taken.
        pub fn insert(self: *Self, key: u64) ?usize {
            std.debug.assert(key != 0);
            std.debug.assert(self.find(key) == null);
            const slot: usize = if (self.free_len != 0) blk: {
                self.free_len -= 1;
                break :blk self.free[self.free_len];
            } else if (self.high_water < capacity) blk: {
                self.high_water += 1;
                break :blk self.high_water - 1;
            } else return null;
            var bucket = home(key);
            while (self.keys[bucket] != 0) bucket = (bucket + 1) & mask;
            self.keys[bucket] = key;
            self.slots[bucket] = @intCast(slot);
            self.len += 1;
            return slot;
        }

        /// The slot for `key`, claiming one when it has none. Null only when
        /// `key` is zero or the table is full.
        pub fn findOrInsert(self: *Self, key: u64) ?struct { slot: usize, inserted: bool } {
            if (key == 0) return null;
            if (self.find(key)) |slot| return .{ .slot = slot, .inserted = false };
            const slot = self.insert(key) orelse return null;
            return .{ .slot = slot, .inserted = true };
        }

        /// Forget `key`, returning the slot it held so the caller can clear
        /// the record, or null when it was not indexed.
        pub fn remove(self: *Self, key: u64) ?usize {
            if (key == 0) return null;
            var bucket = home(key);
            while (true) : (bucket = (bucket + 1) & mask) {
                const held = self.keys[bucket];
                if (held == key) break;
                if (held == 0) return null;
            }
            const slot: usize = self.slots[bucket];
            // Backward-shift deletion: pull later entries of the same probe
            // run into the hole unless their home lies strictly between the
            // hole and where they sit, which would put them before home.
            var hole = bucket;
            var next = (bucket + 1) & mask;
            while (self.keys[next] != 0) : (next = (next + 1) & mask) {
                const displacement = (next -% home(self.keys[next])) & mask;
                const gap = (next -% hole) & mask;
                if (displacement >= gap) {
                    self.keys[hole] = self.keys[next];
                    self.slots[hole] = self.slots[next];
                    hole = next;
                }
            }
            self.keys[hole] = 0;
            self.slots[hole] = 0;
            self.free[self.free_len] = @intCast(slot);
            self.free_len += 1;
            self.len -= 1;
            return slot;
        }

        pub fn reset(self: *Self) void {
            self.* = .{};
        }

        pub fn full(self: *const Self) bool {
            return self.len == capacity;
        }

        /// One past the highest slot ever handed out.
        pub fn highWater(self: *const Self) usize {
            return self.high_water;
        }
    };
}

test "a slot index finds, reuses and refuses in constant time" {
    var index: SlotIndex(4) = .{};
    try std.testing.expect(index.find(0x10) == null);
    const a = index.insert(0x10).?;
    const b = index.insert(0x20).?;
    const c = index.insert(0x30).?;
    const d = index.insert(0x40).?;
    try std.testing.expectEqual(@as(usize, 0), a);
    try std.testing.expectEqual(@as(usize, 3), d);
    try std.testing.expect(index.full());
    try std.testing.expect(index.insert(0x50) == null);
    try std.testing.expectEqual(b, index.find(0x20).?);
    try std.testing.expectEqual(c, index.remove(0x30).?);
    try std.testing.expect(index.find(0x30) == null);
    try std.testing.expect(index.remove(0x30) == null);
    // The released slot is the next one handed out.
    try std.testing.expectEqual(c, index.insert(0x50).?);
    try std.testing.expectEqual(@as(usize, 4), index.highWater());
    const again = index.findOrInsert(0x50).?;
    try std.testing.expect(!again.inserted);
    try std.testing.expectEqual(c, again.slot);
    try std.testing.expect(index.findOrInsert(0) == null);
    index.reset();
    try std.testing.expect(index.find(0x10) == null);
    try std.testing.expectEqual(@as(usize, 0), index.highWater());
}

test "a slot index agrees with a reference map through heavy churn" {
    // Synthetic handles are a counter stepped by 0x10, as the forwarder
    // allocates them; random frees and reinserts exercise every
    // backward-shift case, including runs that wrap past the last bucket.
    const capacity = 257;
    var index: SlotIndex(capacity) = .{};
    var reference = std.AutoHashMap(u64, usize).init(std.testing.allocator);
    defer reference.deinit();
    var owner: [capacity]u64 = @splat(0);
    var prng = std.Random.DefaultPrng.init(0x5107_1DE7);
    const random = prng.random();
    var next_handle: u64 = 0xfffff50000000001;
    for (0..200_000) |_| {
        const roll = random.uintLessThan(u32, 100);
        if (roll < 55) {
            const handle = next_handle;
            next_handle +%= 0x10;
            if (index.insert(handle)) |slot| {
                try std.testing.expectEqual(@as(u64, 0), owner[slot]);
                owner[slot] = handle;
                try reference.put(handle, slot);
            } else {
                try std.testing.expectEqual(@as(usize, capacity), reference.count());
            }
        } else if (reference.count() != 0) {
            // Remove a random live handle.
            var slot = random.uintLessThan(usize, capacity);
            while (owner[slot] == 0) slot = (slot + 1) % capacity;
            const handle = owner[slot];
            try std.testing.expectEqual(slot, index.remove(handle).?);
            owner[slot] = 0;
            _ = reference.remove(handle);
        }
        if (random.uintLessThan(u32, 16) == 0) {
            var it = reference.iterator();
            while (it.next()) |entry| {
                try std.testing.expectEqual(entry.value_ptr.*, index.find(entry.key_ptr.*).?);
            }
            try std.testing.expectEqual(reference.count(), index.len);
        }
        try std.testing.expect(index.find(next_handle) == null);
    }
}
