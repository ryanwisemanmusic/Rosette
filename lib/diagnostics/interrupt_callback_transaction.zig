//! Stateful Xenia PowerPC graphics-callback transaction evidence.

const std = @import("std");
const contract = @import("xenia_interrupt_callback_contract");

pub const Stage = contract.Stage;
pub const Effect = contract.Effect;
pub const Finding = contract.Finding;
pub const Domain = contract.Domain;

pub const Ledger = struct {
    domain: Domain = .xenia_powerpc,
    observed_mask: u8 = 0,
    registrations: u64 = 0,
    dispatch_attempts: u64 = 0,
    callback_returns: u64 = 0,
    dispatch_skips: u64 = 0,
    dispatch_deferrals: u64 = 0,
    context_before_samples: u64 = 0,
    context_after_samples: u64 = 0,
    context_changes: u64 = 0,
    payload_samples: u64 = 0,
    payload_changes: u64 = 0,
    payload_appearances: u64 = 0,
    callback_address: u32 = 0,
    user_data: u32 = 0,
    last_dispatch_id: u64 = 0,
    last_source: u32 = 0,
    last_cpu: u32 = 0,
    last_duration_ms: u64 = 0,
    first_step: u64 = 0,
    last_step: u64 = 0,

    fn observe(self: *Ledger, stage: Stage, step: u64) void {
        if (self.observed_mask == 0) self.first_step = step;
        self.observed_mask |= contract.bit(stage);
        self.last_step = step;
    }

    pub fn observeRegistration(self: *Ledger, count: u64, callback: u32, user_data: u32, step: u64) void {
        self.registrations = @max(self.registrations, count);
        self.callback_address = callback;
        self.user_data = user_data;
        self.observe(.registered, step);
    }

    pub fn observeDispatch(self: *Ledger, count: u64, source: u32, cpu: u32, step: u64) void {
        self.dispatch_attempts = @max(self.dispatch_attempts, count);
        self.last_dispatch_id = @max(self.last_dispatch_id, count);
        self.last_source = source;
        self.last_cpu = cpu;
        self.observe(.dispatch_attempted, step);
    }

    pub fn observeCompletion(
        self: *Ledger,
        id: u64,
        attempts: u64,
        completions: u64,
        callback: u32,
        source: u32,
        cpu: u32,
        duration_ms: u64,
        payload_before: bool,
        payload_after: bool,
        payload_changed: bool,
        step: u64,
    ) void {
        self.dispatch_attempts = @max(self.dispatch_attempts, attempts);
        self.callback_returns = @max(self.callback_returns, completions);
        self.last_dispatch_id = @max(self.last_dispatch_id, id);
        self.callback_address = callback;
        self.last_source = source;
        self.last_cpu = cpu;
        self.last_duration_ms = duration_ms;
        self.payload_samples +|= 1;
        if (payload_changed) self.payload_changes +|= 1;
        if (!payload_before and payload_after) self.payload_appearances +|= 1;
        self.observe(.registered, step);
        self.observe(.dispatch_attempted, step);
        self.observe(.callback_returned, step);
    }

    pub fn observeSkip(self: *Ledger) void {
        self.dispatch_skips +|= 1;
    }

    pub fn observeDeferral(self: *Ledger, total: u64) void {
        self.dispatch_deferrals = @max(self.dispatch_deferrals, total);
    }

    pub fn observeContextBefore(self: *Ledger) void {
        self.context_before_samples +|= 1;
    }

    pub fn observeContextAfter(self: *Ledger, changed: bool) void {
        self.context_after_samples +|= 1;
        if (changed) self.context_changes +|= 1;
    }

    pub fn effect(self: *const Ledger) Effect {
        if (self.payload_appearances != 0) return .payload_appeared;
        if (self.payload_changes != 0) return .payload_changed;
        if (self.payload_samples != 0) return .no_sampled_ring_change;
        return .unobserved;
    }

    pub fn finding(self: *const Ledger) Finding {
        return contract.finding(self.observed_mask, self.effect());
    }

    pub fn firstGap(self: *const Ledger) ?Stage {
        return contract.firstGap(self.observed_mask);
    }

    pub fn counterInvariantHolds(self: *const Ledger) bool {
        return self.callback_returns <= self.dispatch_attempts;
    }
};

test "completion proves the Xenia callback transaction without a ring effect" {
    var ledger = Ledger{};
    ledger.observeRegistration(1, 0x821951F8, 0x40001F00, 100);
    ledger.observeCompletion(168, 168, 168, 0x821951F8, 0, 2, 0, false, false, false, 200);
    try std.testing.expectEqual(Finding.returning_no_sampled_ring_effect, ledger.finding());
    try std.testing.expect(ledger.firstGap() == null);
    try std.testing.expect(ledger.counterInvariantHolds());
}

test "dispatch without return names the callback executor boundary" {
    var ledger = Ledger{};
    ledger.observeRegistration(1, 0x821951F8, 0, 100);
    ledger.observeDispatch(1, 0, 2, 110);
    try std.testing.expectEqual(Stage.callback_returned, ledger.firstGap().?);
    try std.testing.expectEqual(Finding.dispatch_no_return, ledger.finding());
    try std.testing.expect(std.mem.indexOf(u8, ledger.finding().guidance(), "callback executor") != null);
}

test "payload appearance is retained as optional effect evidence" {
    var ledger = Ledger{};
    ledger.observeCompletion(1, 1, 1, 1, 0, 2, 3, false, true, true, 100);
    try std.testing.expectEqual(Effect.payload_appeared, ledger.effect());
    try std.testing.expectEqual(Finding.returning_with_ring_effect, ledger.finding());
}
