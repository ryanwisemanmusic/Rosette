//! Bounded address-to-slot index for Rosetta's guest SRW lock records.
//!
//! Lock records are allocated once and live for the process lifetime. The
//! dispatch lock serializes their insertion and lookup, so this index needs no
//! atomics and can replace a repeated scan of the 256-record table.

const std = @import("std");

pub fn Index(comptime entry_capacity: usize) type {
    comptime {
        if (entry_capacity < 2 or !std.math.isPowerOfTwo(entry_capacity))
            @compileError("SRW index capacity must be a power of two >= 2");
    }

    const table_capacity = entry_capacity * 2;
    return struct {
        const Self = @This();
        const Entry = struct {
            address: u64 = 0,
            slot: usize = 0,
        };

        entries: [table_capacity]Entry = @splat(.{}),

        fn hash(address: u64) usize {
            var value = address;
            value ^= value >> 30;
            value *%= 0xBF58_476D_1CE4_E5B9;
            value ^= value >> 27;
            value *%= 0x94D0_49BB_1331_11EB;
            value ^= value >> 31;
            return @intCast(value & (table_capacity - 1));
        }

        pub fn find(self: *const Self, address: u64) ?usize {
            if (address == 0) return null;
            var index = hash(address);
            for (0..table_capacity) |_| {
                const entry = self.entries[index];
                if (entry.address == address) return entry.slot;
                if (entry.address == 0) return null;
                index = (index + 1) & (table_capacity - 1);
            }
            return null;
        }

        /// Returns false only if the bounded table is full or an address was
        /// accidentally assigned to two lock slots.
        pub fn insert(self: *Self, address: u64, slot: usize) bool {
            if (address == 0) return false;
            var index = hash(address);
            for (0..table_capacity) |_| {
                const entry = &self.entries[index];
                if (entry.address == address) return entry.slot == slot;
                if (entry.address == 0) {
                    entry.* = .{ .address = address, .slot = slot };
                    return true;
                }
                index = (index + 1) & (table_capacity - 1);
            }
            return false;
        }
    };
}

test "SRW lock index resolves colliding addresses and rejects slot reassignment" {
    const SmallIndex = Index(8);
    var index: SmallIndex = .{};
    var keys: [6]u64 = undefined;
    var found: usize = 0;
    var candidate: u64 = 1;
    while (found < keys.len) : (candidate += 1) {
        if (SmallIndex.hash(candidate) != 15) continue;
        keys[found] = candidate;
        found += 1;
    }

    for (keys, 0..) |key, slot| try std.testing.expect(index.insert(key, slot));
    for (keys, 0..) |key, slot| try std.testing.expectEqual(@as(?usize, slot), index.find(key));
    try std.testing.expect(index.insert(keys[2], 2));
    try std.testing.expect(!index.insert(keys[2], 7));
    try std.testing.expectEqual(@as(?usize, null), index.find(0));
    try std.testing.expectEqual(@as(?usize, null), index.find(0xBAD));
}
