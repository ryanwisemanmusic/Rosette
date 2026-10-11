//! Publish the first parallel guest fault as one immutable, race-safe record.

const std = @import("std");

pub fn First(comptime Payload: type) type {
    return struct {
        const Self = @This();

        /// 0 = empty, 1 = writer owns the slot, 2 = payload is published.
        state: std.atomic.Value(u8) = std.atomic.Value(u8).init(0),
        payload: Payload = undefined,

        pub fn capture(self: *Self, payload: Payload) bool {
            if (self.state.cmpxchgStrong(0, 1, .acq_rel, .acquire) != null) return false;
            self.payload = payload;
            self.state.store(2, .release);
            return true;
        }

        pub fn read(self: *const Self) ?Payload {
            if (self.state.load(.acquire) != 2) return null;
            return self.payload;
        }

        /// Call only after all producers from the previous run have joined.
        pub fn reset(self: *Self) void {
            self.state.store(0, .release);
        }
    };
}

test "parallel fault snapshot publishes one complete first-writer payload" {
    const Snapshot = First(struct { rip: u64, slot: usize });
    var snapshot = Snapshot{};
    try std.testing.expect(snapshot.read() == null);
    try std.testing.expect(snapshot.capture(.{ .rip = 0x1408b944a, .slot = 7 }));
    try std.testing.expect(!snapshot.capture(.{ .rip = 0xdead, .slot = 2 }));
    const captured = snapshot.read().?;
    try std.testing.expectEqual(@as(u64, 0x1408b944a), captured.rip);
    try std.testing.expectEqual(@as(usize, 7), captured.slot);
    snapshot.reset();
    try std.testing.expect(snapshot.read() == null);
}
