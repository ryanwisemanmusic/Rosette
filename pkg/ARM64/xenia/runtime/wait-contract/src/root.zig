//! ARM64-route wait/signal semantics for cross-architecture bridge checks.
//!
//! This is not a scheduler. It only records the invariant that a consuming
//! wait cannot succeed without consuming one pending signal. The model is the
//! same on every route; only the route identity below differs.

const std = @import("std");

pub const host_architecture = "arm64";
pub const host_codegen = "arm64-native-bridge";

pub const EventMode = enum {
    consume_one,
    manual_reset,
};

pub const WaitResult = enum {
    blocked,
    signaled,
};

pub const WaitEvent = struct {
    mode: EventMode,
    pending_signals: u64 = 0,
    signal_count: u64 = 0,
    blocked_wait_count: u64 = 0,
    successful_wait_count: u64 = 0,
    consumed_signal_count: u64 = 0,
    invalid_success_count: u64 = 0,

    pub fn init(mode: EventMode) WaitEvent {
        return .{ .mode = mode };
    }

    pub fn signal(self: *WaitEvent) void {
        self.signal_count +|= 1;
        switch (self.mode) {
            .consume_one => self.pending_signals +|= 1,
            .manual_reset => self.pending_signals = 1,
        }
    }

    pub fn broadcast(self: *WaitEvent, waiter_count: u64) void {
        self.signal_count +|= waiter_count;
        switch (self.mode) {
            .consume_one => self.pending_signals +|= waiter_count,
            .manual_reset => self.pending_signals = 1,
        }
    }

    pub fn wait(self: *WaitEvent) WaitResult {
        if (self.mode == .manual_reset) {
            if (self.pending_signals == 0) {
                self.blocked_wait_count +|= 1;
                return .blocked;
            }
            self.successful_wait_count +|= 1;
            return .signaled;
        }

        if (self.pending_signals == 0) {
            self.blocked_wait_count +|= 1;
            return .blocked;
        }

        self.pending_signals -= 1;
        self.successful_wait_count +|= 1;
        self.consumed_signal_count +|= 1;
        return .signaled;
    }

    /// Records an externally observed successful wait. This is intentionally
    /// separate from `wait`: an adapter can use it to audit a native runtime
    /// without pretending it performed the native operation itself.
    pub fn observeExternalSuccess(self: *WaitEvent, consumed_signal: bool) void {
        self.successful_wait_count +|= 1;
        if (consumed_signal) {
            self.consumed_signal_count +|= 1;
        } else if (self.mode == .consume_one) {
            self.invalid_success_count +|= 1;
        }
    }

    pub fn reset(self: *WaitEvent) void {
        self.pending_signals = 0;
    }

    pub fn invariantHolds(self: *const WaitEvent) bool {
        if (self.mode == .manual_reset) return self.invalid_success_count == 0;
        return self.invalid_success_count == 0 and
            self.successful_wait_count == self.consumed_signal_count;
    }
};

test "package identity is the ARM64 native bridge route" {
    try std.testing.expectEqualStrings("arm64", host_architecture);
    try std.testing.expectEqualStrings("arm64-native-bridge", host_codegen);
}

test "a consuming wait blocks, consumes one signal, then blocks again" {
    var event = WaitEvent.init(.consume_one);
    try std.testing.expectEqual(WaitResult.blocked, event.wait());
    event.signal();
    try std.testing.expectEqual(WaitResult.signaled, event.wait());
    try std.testing.expectEqual(WaitResult.blocked, event.wait());
    try std.testing.expectEqual(@as(u64, 1), event.consumed_signal_count);
    try std.testing.expect(event.invariantHolds());
}

test "a manual-reset event stays signaled until reset" {
    var event = WaitEvent.init(.manual_reset);
    event.signal();
    try std.testing.expectEqual(WaitResult.signaled, event.wait());
    try std.testing.expectEqual(WaitResult.signaled, event.wait());
    event.reset();
    try std.testing.expectEqual(WaitResult.blocked, event.wait());
    try std.testing.expect(event.invariantHolds());
}

test "the audit catches a successful consuming wait with no consumed signal" {
    var event = WaitEvent.init(.consume_one);
    event.observeExternalSuccess(false);
    try std.testing.expectEqual(@as(u64, 1), event.invalid_success_count);
    try std.testing.expect(!event.invariantHolds());
}

test "broadcast supplies one consumable signal per waiter" {
    var event = WaitEvent.init(.consume_one);
    event.broadcast(3);
    try std.testing.expectEqual(WaitResult.signaled, event.wait());
    try std.testing.expectEqual(WaitResult.signaled, event.wait());
    try std.testing.expectEqual(WaitResult.signaled, event.wait());
    try std.testing.expectEqual(WaitResult.blocked, event.wait());
    try std.testing.expect(event.invariantHolds());
}
