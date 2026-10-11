//! Fixed-capacity open-addressed set for native Vulkan handles.
//!
//! Vulkan command paths repeatedly ask whether a native object belongs to a
//! Rosetta-specific workaround. A dense list makes that check linear in the
//! number of pipelines created; this bounded set keeps lookup and insert
//! expected O(1) without allocating in the command path.

const std = @import("std");

pub fn Set(comptime capacity: usize) type {
    comptime {
        if (capacity < 2 or !std.math.isPowerOfTwo(capacity))
            @compileError("handle-set capacity must be a power of two >= 2");
    }

    return struct {
        const Self = @This();

        entries: [capacity]u64 = @splat(0),
        len: usize = 0,

        pub const InsertResult = enum { inserted, existing, full };

        fn slot(handle: u64) usize {
            var value = handle;
            value ^= value >> 30;
            value *%= 0xBF58_476D_1CE4_E5B9;
            value ^= value >> 27;
            value *%= 0x94D0_49BB_1331_11EB;
            value ^= value >> 31;
            return @intCast(value & (capacity - 1));
        }

        pub fn contains(self: *const Self, handle: u64) bool {
            if (handle == 0) return false;
            var index = slot(handle);
            for (0..capacity) |_| {
                const present = self.entries[index];
                if (present == handle) return true;
                if (present == 0) return false;
                index = (index + 1) & (capacity - 1);
            }
            return false;
        }

        pub fn insert(self: *Self, handle: u64) InsertResult {
            if (handle == 0) return .full;
            var index = slot(handle);
            for (0..capacity) |_| {
                const present = self.entries[index];
                if (present == handle) return .existing;
                if (present == 0) {
                    self.entries[index] = handle;
                    self.len += 1;
                    return .inserted;
                }
                index = (index + 1) & (capacity - 1);
            }
            return .full;
        }

        /// Removes a handle and re-inserts the rest of its probe cluster so
        /// lookup can continue treating the first empty slot as a hard stop.
        pub fn remove(self: *Self, handle: u64) bool {
            if (handle == 0) return false;
            var index = slot(handle);
            for (0..capacity) |_| {
                const present = self.entries[index];
                if (present == 0) return false;
                if (present == handle) {
                    self.entries[index] = 0;
                    self.len -= 1;
                    var next = (index + 1) & (capacity - 1);
                    while (self.entries[next] != 0) {
                        const displaced = self.entries[next];
                        self.entries[next] = 0;
                        self.len -= 1;
                        _ = self.insert(displaced);
                        next = (next + 1) & (capacity - 1);
                    }
                    return true;
                }
                index = (index + 1) & (capacity - 1);
            }
            return false;
        }
    };
}

test "handle set keeps colliding handles findable through removal and wraparound" {
    const SmallSet = Set(8);
    var set: SmallSet = .{};
    var keys: [5]u64 = undefined;
    var found: usize = 0;
    var candidate: u64 = 1;
    while (found < keys.len) : (candidate += 1) {
        if (SmallSet.slot(candidate) != 7) continue;
        keys[found] = candidate;
        found += 1;
    }

    for (keys) |key| try std.testing.expectEqual(SmallSet.InsertResult.inserted, set.insert(key));
    try std.testing.expectEqual(SmallSet.InsertResult.existing, set.insert(keys[2]));
    try std.testing.expectEqual(@as(usize, keys.len), set.len);
    for (keys) |key| try std.testing.expect(set.contains(key));

    try std.testing.expect(set.remove(keys[0]));
    try std.testing.expect(!set.contains(keys[0]));
    for (keys[1..]) |key| try std.testing.expect(set.contains(key));
    try std.testing.expectEqual(SmallSet.InsertResult.inserted, set.insert(0xFFFF_FFFF_FFFF_FFFE));
    try std.testing.expect(set.contains(0xFFFF_FFFF_FFFF_FFFE));
}

test "handle set reports capacity instead of overwriting a live handle" {
    const SmallSet = Set(4);
    var set: SmallSet = .{};
    for (1..5) |key| try std.testing.expectEqual(SmallSet.InsertResult.inserted, set.insert(@intCast(key)));
    try std.testing.expectEqual(SmallSet.InsertResult.full, set.insert(5));
    try std.testing.expectEqual(@as(usize, 4), set.len);
    for (1..5) |key| try std.testing.expect(set.contains(@intCast(key)));
}
