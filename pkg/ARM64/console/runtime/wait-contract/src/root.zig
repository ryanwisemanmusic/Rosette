//! Static wait/signal semantics for the ARM64 Xenia route.

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

pub fn waitResult(mode: EventMode, pending_signals: u64) WaitResult {
    _ = mode;
    return if (pending_signals == 0) .blocked else .signaled;
}

pub fn signalPending(mode: EventMode, pending_signals: u64) u64 {
    return switch (mode) {
        .consume_one => pending_signals +| 1,
        .manual_reset => 1,
    };
}

pub fn broadcastPending(mode: EventMode, pending_signals: u64, waiter_count: u64) u64 {
    return switch (mode) {
        .consume_one => pending_signals +| waiter_count,
        .manual_reset => 1,
    };
}

pub fn resetPending(pending_signals: u64) u64 {
    _ = pending_signals;
    return 0;
}

pub fn consumesOnSuccess(mode: EventMode) bool {
    return mode == .consume_one;
}

pub fn invariantHolds(
    mode: EventMode,
    successful_wait_count: u64,
    consumed_signal_count: u64,
    invalid_success_count: u64,
) bool {
    if (invalid_success_count != 0) return false;
    return mode == .manual_reset or successful_wait_count == consumed_signal_count;
}

test "package identity is the ARM64 native bridge route" {
    try std.testing.expectEqualStrings("arm64", host_architecture);
    try std.testing.expectEqualStrings("arm64-native-bridge", host_codegen);
}

test "pure wait decisions preserve consuming and manual-reset semantics" {
    try std.testing.expectEqual(WaitResult.blocked, waitResult(.consume_one, 0));
    try std.testing.expectEqual(WaitResult.signaled, waitResult(.consume_one, 1));
    try std.testing.expectEqual(@as(u64, 1), signalPending(.manual_reset, 9));
    try std.testing.expectEqual(@as(u64, 3), broadcastPending(.consume_one, 0, 3));
    try std.testing.expectEqual(@as(u64, 0), resetPending(9));
    try std.testing.expect(consumesOnSuccess(.consume_one));
    try std.testing.expect(!consumesOnSuccess(.manual_reset));
}

test "the pure invariant rejects an unconsumed successful consuming wait" {
    try std.testing.expect(invariantHolds(.consume_one, 2, 2, 0));
    try std.testing.expect(!invariantHolds(.consume_one, 2, 1, 0));
    try std.testing.expect(!invariantHolds(.consume_one, 1, 1, 1));
    try std.testing.expect(invariantHolds(.manual_reset, 2, 0, 0));
}
