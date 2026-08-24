//! Runtime wait/signal ledger.
//!
//! The package supplies pure event semantics. This module owns mutable
//! observations of a live bridge or pthread-facing wait object.

const contract = @import("xenia_wait_contract");

pub const EventMode = contract.EventMode;
pub const WaitResult = contract.WaitResult;

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
        self.pending_signals = contract.signalPending(self.mode, self.pending_signals);
    }

    pub fn broadcast(self: *WaitEvent, waiter_count: u64) void {
        self.signal_count +|= waiter_count;
        self.pending_signals = contract.broadcastPending(
            self.mode,
            self.pending_signals,
            waiter_count,
        );
    }

    pub fn wait(self: *WaitEvent) WaitResult {
        const result = contract.waitResult(self.mode, self.pending_signals);
        if (result == .blocked) {
            self.blocked_wait_count +|= 1;
            return result;
        }

        self.successful_wait_count +|= 1;
        if (contract.consumesOnSuccess(self.mode)) {
            self.pending_signals -= 1;
            self.consumed_signal_count +|= 1;
        }
        return result;
    }

    pub fn observeExternalSuccess(self: *WaitEvent, consumed_signal: bool) void {
        self.successful_wait_count +|= 1;
        if (consumed_signal) {
            self.consumed_signal_count +|= 1;
        } else if (contract.consumesOnSuccess(self.mode)) {
            self.invalid_success_count +|= 1;
        }
    }

    pub fn reset(self: *WaitEvent) void {
        self.pending_signals = contract.resetPending(self.pending_signals);
    }

    pub fn invariantHolds(self: *const WaitEvent) bool {
        return contract.invariantHolds(
            self.mode,
            self.successful_wait_count,
            self.consumed_signal_count,
            self.invalid_success_count,
        );
    }
};

test "runtime ledger keeps mutable state outside the package" {
    var event = WaitEvent.init(.consume_one);
    try @import("std").testing.expectEqual(WaitResult.blocked, event.wait());
    event.broadcast(2);
    try @import("std").testing.expectEqual(WaitResult.signaled, event.wait());
    try @import("std").testing.expectEqual(WaitResult.signaled, event.wait());
    try @import("std").testing.expectEqual(WaitResult.blocked, event.wait());
    try @import("std").testing.expectEqual(@as(u64, 2), event.consumed_signal_count);
    try @import("std").testing.expect(event.invariantHolds());
}
