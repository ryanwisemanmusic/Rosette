//! Static wait/signal policies for host routes.
//!
//! This package owns only pure decisions. The pending signal count and
//! observations of a live pthread or kernel object belong to lib.

const std = @import("std");
const wait_policy = @import("wait_policy.zig");

pub const host_architecture = "x86_64";
pub const host_codegen = "xbyak-x86_64";

pub const EventMode = wait_policy.EventMode;
pub const WaitResult = wait_policy.WaitResult;
pub const WaitContract = wait_policy.WaitContract;

pub fn waitResult(mode: EventMode, pending_signals: u64) WaitResult {
    return (WaitContract{ .mode = mode }).result(pending_signals);
}

pub fn signalPending(mode: EventMode, pending_signals: u64) u64 {
    return (WaitContract{ .mode = mode }).signal(pending_signals);
}

pub fn broadcastPending(mode: EventMode, pending_signals: u64, waiter_count: u64) u64 {
    return (WaitContract{ .mode = mode }).broadcast(pending_signals, waiter_count);
}

pub fn resetPending(pending_signals: u64) u64 {
    return (WaitContract{ .mode = .consume_one }).reset(pending_signals);
}

pub fn consumesOnSuccess(mode: EventMode) bool {
    return (WaitContract{ .mode = mode }).consumes();
}

pub fn invariantHolds(
    mode: EventMode,
    successful_wait_count: u64,
    consumed_signal_count: u64,
    invalid_success_count: u64,
) bool {
    return (WaitContract{ .mode = mode }).invariantHolds(
        successful_wait_count,
        consumed_signal_count,
        invalid_success_count,
    );
}

test "package identity is the x86 Xbyak route" {
    try std.testing.expectEqualStrings("x86_64", host_architecture);
    try std.testing.expectEqualStrings("xbyak-x86_64", host_codegen);
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
