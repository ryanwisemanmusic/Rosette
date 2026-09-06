//! Cross-source provenance for GPU bootstrap milestones.
//!
//! The GPU bootstrap contract and the execution boundary gate answer different
//! questions.  The former records a guest-visible breadcrumb (normally emitted
//! by Xenia), while the latter records an instruction-trace crossing in the
//! host process.  Treating either one as the other loses useful information and
//! makes a diagnostic probe capable of retracting a real guest observation.
//!
//! This ledger deliberately keeps the sources separate.  A guest breadcrumb is
//! not promoted to an instruction tracepoint, and a call-site probe miss is not
//! promoted to a failed guest call.  The result is a small, allocation-free
//! reconciliation layer that can be used by the strict admission and
//! substantiation gates without weakening either gate.

const std = @import("std");
const bootstrap = @import("bootstrap.zig");

pub const Finding = enum(u8) {
    unobserved,
    /// A callsite probe ran, but none of its direct execution channels hit and
    /// no guest breadcrumb or tracepoint independently observed the milestone.
    /// This is observer debt, not proof that the guest skipped the call.
    callsite_blind,
    guest_only,
    guest_only_callsite_blind,
    trace_only,
    corroborated,

    pub fn label(self: Finding) []const u8 {
        return switch (self) {
            .unobserved => "unobserved",
            .callsite_blind => "callsite-blind",
            .guest_only => "guest-only",
            .guest_only_callsite_blind => "guest-only-callsite-blind",
            .trace_only => "trace-only",
            .corroborated => "corroborated",
        };
    }
};

pub const Record = struct {
    guest_count: u64 = 0,
    guest_first_step: u64 = 0,
    guest_last_step: u64 = 0,

    trace_count: u64 = 0,
    trace_first_step: u64 = 0,
    trace_last_step: u64 = 0,

    callsite_probe_count: u64 = 0,
    callsite_first_step: u64 = 0,
    callsite_last_step: u64 = 0,
    callsite_pc_hits: u64 = 0,
    callsite_lr_hits: u64 = 0,
    callsite_ctr_hits: u64 = 0,
    callsite_branch_probe_hits: u64 = 0,
    callsite_near_direct_bl_hits: u64 = 0,
    callsite_entry_bctrl_hits: u64 = 0,
    callsite_near_value_ref_hits: u64 = 0,
    callsite_entry_value_ref_hits: u64 = 0,

    configuration_count: u64 = 0,
    configuration_first_step: u64 = 0,
    configuration_last_step: u64 = 0,
    configuration_mapped_count: u64 = 0,

    pub fn guestObserved(self: Record) bool {
        return self.guest_count != 0;
    }

    pub fn traceObserved(self: Record) bool {
        return self.trace_count != 0;
    }

    pub fn callsiteObserved(self: Record) bool {
        return self.callsite_probe_count != 0;
    }

    pub fn callsiteBlind(self: Record) bool {
        return self.callsiteObserved() and
            self.callsite_pc_hits == 0 and
            self.callsite_lr_hits == 0 and
            self.callsite_ctr_hits == 0 and
            self.callsite_branch_probe_hits == 0;
    }

    pub fn configured(self: Record) bool {
        return self.configuration_count != 0;
    }

    pub fn finding(self: Record) Finding {
        if (self.guestObserved() and self.traceObserved()) return .corroborated;
        if (self.guestObserved()) {
            if (self.callsiteBlind()) return .guest_only_callsite_blind;
            return .guest_only;
        }
        if (self.traceObserved()) return .trace_only;
        if (self.callsiteBlind()) return .callsite_blind;
        return .unobserved;
    }

    pub fn guidance(self: Record) []const u8 {
        return switch (self.finding()) {
            .unobserved => "no source has observed this bootstrap milestone",
            .callsite_blind => "callsite probe ran without direct execution evidence; its miss is observer debt, not proof that the guest skipped this milestone",
            .guest_only => "guest breadcrumb observed; no matching execution tracepoint was crossed",
            .guest_only_callsite_blind => "guest breadcrumb observed; the callsite probe missed it, so the probe is not an execution authority",
            .trace_only => "execution tracepoint crossed; no matching guest breadcrumb was retained",
            .corroborated => "guest breadcrumb and execution tracepoint agree",
        };
    }

    pub fn stableFingerprint(self: Record) u64 {
        var result: u64 = 0xcbf29ce484222325;
        result = mix(result, self.guest_count);
        result = mix(result, self.trace_count);
        result = mix(result, self.callsite_probe_count);
        result = mix(result, self.callsite_pc_hits);
        result = mix(result, self.callsite_lr_hits);
        result = mix(result, self.callsite_ctr_hits);
        result = mix(result, self.callsite_branch_probe_hits);
        result = mix(result, self.callsite_near_direct_bl_hits);
        result = mix(result, self.callsite_entry_bctrl_hits);
        result = mix(result, self.callsite_near_value_ref_hits);
        result = mix(result, self.callsite_entry_value_ref_hits);
        result = mix(result, self.configuration_count);
        result = mix(result, self.configuration_mapped_count);
        return result;
    }

    fn mix(seed: u64, value: u64) u64 {
        var result = seed ^ value;
        result *%= 0x100000001b3;
        result ^= result >> 29;
        result *%= 0x9e3779b185ebca87;
        return result;
    }
};

pub const Summary = struct {
    guest_observed: u32 = 0,
    trace_observed: u32 = 0,
    corroborated: u32 = 0,
    guest_only: u32 = 0,
    guest_only_callsite_blind: u32 = 0,
    trace_only: u32 = 0,
    callsite_blind: u32 = 0,
    configured: u32 = 0,
};

pub const Ledger = struct {
    records: [bootstrap.step_count]Record = [_]Record{.{}} ** bootstrap.step_count,

    pub fn record(self: *const Ledger, step: bootstrap.Step) Record {
        return self.records[@intFromEnum(step)];
    }

    pub fn observeGuest(self: *Ledger, step: bootstrap.Step, guest_step: u64) void {
        var item = &self.records[@intFromEnum(step)];
        item.guest_count +|= 1;
        if (item.guest_count == 1) item.guest_first_step = guest_step;
        item.guest_last_step = guest_step;
    }

    pub fn observeTrace(
        self: *Ledger,
        step: bootstrap.Step,
        trace_hits: u64,
        first_step: u64,
        last_step: u64,
    ) void {
        if (trace_hits == 0) return;
        var item = &self.records[@intFromEnum(step)];
        if (trace_hits > item.trace_count) item.trace_count = trace_hits;
        if (item.trace_count == trace_hits or item.trace_first_step == 0) {
            item.trace_first_step = first_step;
        }
        if (last_step >= item.trace_last_step) item.trace_last_step = last_step;
    }

    pub fn observeCallsite(
        self: *Ledger,
        step: bootstrap.Step,
        probe_step: u64,
        pc_hit: bool,
        lr_hit: bool,
        ctr_hit: bool,
        branch_targets_probe: bool,
        near_direct_bl_hits: u64,
        entry_bctrl_hits: u64,
        near_value_ref_hits: u64,
        entry_value_ref_hits: u64,
    ) void {
        var item = &self.records[@intFromEnum(step)];
        item.callsite_probe_count +|= 1;
        if (item.callsite_probe_count == 1) item.callsite_first_step = probe_step;
        item.callsite_last_step = probe_step;
        item.callsite_pc_hits +|= @intFromBool(pc_hit);
        item.callsite_lr_hits +|= @intFromBool(lr_hit);
        item.callsite_ctr_hits +|= @intFromBool(ctr_hit);
        item.callsite_branch_probe_hits +|= @intFromBool(branch_targets_probe);
        item.callsite_near_direct_bl_hits +|= near_direct_bl_hits;
        item.callsite_entry_bctrl_hits +|= entry_bctrl_hits;
        item.callsite_near_value_ref_hits +|= near_value_ref_hits;
        item.callsite_entry_value_ref_hits +|= entry_value_ref_hits;
    }

    pub fn observeConfiguration(
        self: *Ledger,
        step: bootstrap.Step,
        configuration_step: u64,
        mapped: bool,
    ) void {
        var item = &self.records[@intFromEnum(step)];
        item.configuration_count +|= 1;
        if (item.configuration_count == 1) item.configuration_first_step = configuration_step;
        item.configuration_last_step = configuration_step;
        if (mapped) item.configuration_mapped_count +|= 1;
    }

    pub fn summary(self: *const Ledger) Summary {
        var result = Summary{};
        for (self.records) |item| {
            if (item.guestObserved()) result.guest_observed += 1;
            if (item.traceObserved()) result.trace_observed += 1;
            if (item.callsiteBlind()) result.callsite_blind += 1;
            if (item.configured()) result.configured += 1;
            switch (item.finding()) {
                .unobserved => {},
                .callsite_blind => {},
                .guest_only => result.guest_only += 1,
                .guest_only_callsite_blind => result.guest_only_callsite_blind += 1,
                .trace_only => result.trace_only += 1,
                .corroborated => result.corroborated += 1,
            }
        }
        return result;
    }

    pub fn stableFingerprint(self: *const Ledger) u64 {
        var result: u64 = 0xcbf29ce484222325;
        for (self.records) |item| result = Record.mix(result, item.stableFingerprint());
        return result;
    }

    pub fn guestObserved(self: *const Ledger, step: bootstrap.Step) bool {
        return self.record(step).guestObserved();
    }

    pub fn traceObserved(self: *const Ledger, step: bootstrap.Step) bool {
        return self.record(step).traceObserved();
    }
};

test "guest execution survives a blind callsite probe" {
    var ledger = Ledger{};
    ledger.observeGuest(.initialize_engines, 2_863_898_889);
    ledger.observeCallsite(.initialize_engines, 2_864_000_000, false, false, false, false, 0, 2, 0, 11);

    const item = ledger.record(.initialize_engines);
    try std.testing.expectEqual(Finding.guest_only_callsite_blind, item.finding());
    try std.testing.expect(item.callsiteBlind());
    try std.testing.expect(item.guestObserved());
    try std.testing.expect(!item.traceObserved());
}

test "a callsite-only miss is explicit observer debt" {
    var ledger = Ledger{};
    ledger.observeCallsite(.initialize_engines, 100, false, false, false, false, 0, 2, 0, 11);

    const item = ledger.record(.initialize_engines);
    try std.testing.expectEqual(Finding.callsite_blind, item.finding());
    try std.testing.expect(item.callsiteBlind());
    try std.testing.expect(!item.guestObserved());
    try std.testing.expect(!item.traceObserved());
    try std.testing.expect(std.mem.indexOf(u8, item.guidance(), "observer debt") != null);
}

test "tracepoint and guest breadcrumb are corroborated" {
    var ledger = Ledger{};
    ledger.observeGuest(.graphics_interrupt_callback, 10);
    ledger.observeTrace(.graphics_interrupt_callback, 3, 11, 20);

    const item = ledger.record(.graphics_interrupt_callback);
    try std.testing.expectEqual(Finding.corroborated, item.finding());
    try std.testing.expectEqual(@as(u32, 1), ledger.summary().corroborated);
}

test "configuration is tracked independently from execution authority" {
    var ledger = Ledger{};
    ledger.observeGuest(.rptr_writeback, 100);
    ledger.observeConfiguration(.rptr_writeback, 101, true);

    const item = ledger.record(.rptr_writeback);
    try std.testing.expectEqual(Finding.guest_only, item.finding());
    try std.testing.expect(item.configured());
    try std.testing.expectEqual(@as(u64, 1), item.configuration_mapped_count);
}

test "stable fingerprint ignores moving timestamps" {
    var first = Ledger{};
    var second = Ledger{};
    first.observeGuest(.initialize_engines, 10);
    second.observeGuest(.initialize_engines, 20);
    first.observeCallsite(.initialize_engines, 11, false, false, false, false, 0, 2, 0, 11);
    second.observeCallsite(.initialize_engines, 21, false, false, false, false, 0, 2, 0, 11);
    try std.testing.expectEqual(first.stableFingerprint(), second.stableFingerprint());
}
