//! Indexed continuation custody. Reuse still requires release plus completed
//! submission serial; uncertain driver state remains permanently quarantined.
const std = @import("std");
pub fn Pool(comptime pool_capacity: usize) type {
    return struct {
        const Self = @This();
        pub const capacity = pool_capacity;
        const words = (capacity + 63) / 64;
        const groups = (words + 63) / 64;
        const map_capacity = std.math.ceilPowerOfTwo(usize, capacity * 2) catch unreachable;
        pub const Entry = struct {
            handle: u64 = 0,
            in_use: bool = false,
            poisoned: bool = false,
            release_after: u64 = 0,
            last_submit: u64 = 0,
        };
        pub const Work = struct {
            acquire_calls: u64 = 0,
            candidate_checks: u64 = 0,
            recording_releases: u64 = 0,
            recording_chunks: u64 = 0,
            recording_host_ns: u64 = 0,
            recording_max_host_ns: u64 = 0,
            find_calls: u64 = 0,
            hash_probes: u64 = 0,
            releases: u64 = 0,
        };
        entries: [capacity]Entry = @splat(.{}),
        count: usize = 0,
        allocated: u64 = 0,
        reuses: u64 = 0,
        exhausted: u64 = 0,
        poisoned_count: u64 = 0,
        available: [words]u64 = @splat(0),
        nonempty: [groups]u64 = @splat(0),
        // No deletions: quarantined handles remain owned by the command pool.
        // Index+1 permits a zero handle in CPU contract tests too.
        handle_slots: [map_capacity]u16 = @splat(0),
        work: Work = .{},
        fn hash(handle: u64) usize {
            var h = handle;
            h = (h ^ (h >> 33)) *% 0xff51afd7ed558ccd;
            h = (h ^ (h >> 33)) *% 0xc4ceb9fe1a85ec53;
            return @intCast((h ^ (h >> 33)) & (map_capacity - 1));
        }
        fn mark(self: *Self, index: usize, free: bool) void {
            const word = index / 64;
            const bit = @as(u64, 1) << @intCast(index % 64);
            if (free) self.available[word] |= bit else self.available[word] &= ~bit;
            const group_bit = @as(u64, 1) << @intCast(word % 64);
            if (self.available[word] != 0) self.nonempty[word / 64] |= group_bit else self.nonempty[word / 64] &= ~group_bit;
        }
        pub fn acquire(self: *Self, completed_serial: u64) ?u64 {
            self.work.acquire_calls +|= 1;
            // Ascending bit order preserves the original lowest-ready entry.
            for (self.nonempty, 0..) |group_mask, group| {
                var candidates = group_mask;
                while (candidates != 0) : (candidates &= candidates - 1) {
                    const word = group * 64 + @ctz(candidates);
                    var bits = self.available[word];
                    while (bits != 0) : (bits &= bits - 1) {
                        const index = word * 64 + @ctz(bits);
                        const entry = &self.entries[index];
                        self.work.candidate_checks +|= 1;
                        if (entry.release_after > completed_serial) continue;
                        std.debug.assert(!entry.poisoned and !entry.in_use);
                        self.mark(index, false);
                        entry.in_use = true;
                        entry.release_after = 0;
                        entry.last_submit = 0;
                        self.reuses +|= 1;
                        return entry.handle;
                    }
                }
            }
            return null;
        }
        pub fn canGrow(self: *const Self) bool {
            return self.count < capacity;
        }
        pub fn add(self: *Self, handle: u64) bool {
            if (self.count == capacity) {
                self.exhausted +|= 1;
                return false;
            }
            const index = self.count;
            self.entries[index] = .{ .handle = handle, .in_use = true };
            self.count += 1;
            self.allocated +|= 1;
            var slot = hash(handle);
            while (self.handle_slots[slot] != 0) : (slot = (slot + 1) & (map_capacity - 1)) {
                // Preserve original find's first-match behavior for duplicate
                // test handles. Real driver handles are distinct while live.
                if (self.entries[self.handle_slots[slot] - 1].handle == handle) return true;
            }
            self.handle_slots[slot] = @intCast(index + 1);
            return true;
        }
        fn findIndex(self: *Self, handle: u64) ?usize {
            self.work.find_calls +|= 1;
            var slot = hash(handle);
            while (true) : (slot = (slot + 1) & (map_capacity - 1)) {
                self.work.hash_probes +|= 1;
                const stored = self.handle_slots[slot];
                if (stored == 0) return null;
                const index = stored - 1;
                if (self.entries[index].handle == handle) return index;
            }
        }
        pub fn noteSubmitted(self: *Self, handle: u64, serial: u64) void {
            if (self.findIndex(handle)) |index| self.entries[index].last_submit = serial;
        }
        pub fn release(self: *Self, handle: u64) void {
            const index = self.findIndex(handle) orelse return;
            const entry = &self.entries[index];
            if (entry.poisoned) return;
            entry.in_use = false;
            entry.release_after = entry.last_submit;
            self.mark(index, true);
            self.work.releases +|= 1;
        }
        pub fn discard(self: *Self, handle: u64) void {
            const index = self.findIndex(handle) orelse return;
            const entry = &self.entries[index];
            if (entry.poisoned) return;
            entry.poisoned = true;
            entry.in_use = false;
            self.mark(index, false);
            self.poisoned_count +|= 1;
        }
    };
}
