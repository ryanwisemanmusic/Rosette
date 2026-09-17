const std = @import("std");

/// The Rosetta boundary at which a guest thread stopped doing useful work.
///
/// This is intentionally independent of the Windows wait implementation.  A
/// wait can be modelled correctly and still be a large part of a run's cost;
/// the ledger makes that cost visible without turning the hot path into a
/// trace stream.
pub const WaitKind = enum(u8) {
    condition,
    timed_condition,
    finite_handle,
    infinite_handle,
    multiple,
    deadline,
    srw_lock,

    pub fn label(self: WaitKind) []const u8 {
        return switch (self) {
            .condition => "condition",
            .timed_condition => "timed_condition",
            .finite_handle => "finite_handle",
            .infinite_handle => "infinite_handle",
            .multiple => "multiple",
            .deadline => "deadline",
            .srw_lock => "srw_lock",
        };
    }
};

pub const Outcome = enum(u8) {
    signaled,
    timed_out,
    immediate,
    unknown,
    aborted,
};

/// The caller that made a wait object observable.  A zero field means the
/// notification came through a boundary that did not have a guest-thread
/// identity, not that Rosetta invented a producer.
pub const SignalEvidence = struct {
    thread_handle: u64 = 0,
    rip: u64 = 0,
};

/// A timeout is evidence about cost, not automatically evidence of a broken
/// wait.  This classification is deliberately derived from the bounded ledger
/// rather than from a single blocked-thread snapshot: a short wait that expires
/// thousands of times is a poll, while one active unsignalled condition is a
/// producer/lost-wakeup candidate.  Keeping the distinction here means every
/// consumer of the ledger uses the same liveness vocabulary.
pub const Classification = enum(u8) {
    no_data,
    expected_deadline,
    periodic_timeout_poll,
    timeout_hotspot,
    lost_wakeup_candidate,
    pending_producer,
    unsignalled_condition,
    mixed_timeout_signal,
    healthy,

    pub fn label(self: Classification) []const u8 {
        return switch (self) {
            .no_data => "no_data",
            .expected_deadline => "expected_deadline",
            .periodic_timeout_poll => "periodic_timeout_poll",
            .timeout_hotspot => "timeout_hotspot",
            .lost_wakeup_candidate => "lost_wakeup_candidate",
            .pending_producer => "pending_producer",
            .unsignalled_condition => "unsignalled_condition",
            .mixed_timeout_signal => "mixed_timeout_signal",
            .healthy => "healthy",
        };
    }

    /// Higher values are more useful to inspect first.  Expected cadence and
    /// already-signalled sites remain visible, but cannot outrank a wait that
    /// has no producer evidence or a condition that has never been notified.
    pub fn priority(self: Classification) u8 {
        return switch (self) {
            .no_data => 0,
            .healthy => 5,
            .expected_deadline => 10,
            .periodic_timeout_poll => 20,
            .mixed_timeout_signal => 45,
            .timeout_hotspot => 60,
            .pending_producer => 70,
            .unsignalled_condition => 80,
            .lost_wakeup_candidate => 90,
        };
    }

    pub fn action(self: Classification) []const u8 {
        return switch (self) {
            .no_data => "no completed wait evidence is available yet",
            .expected_deadline => "verify the guest clock reaches the stored deadline; this is expected pacing, not a deadlock finding",
            .periodic_timeout_poll => "correlate the caller and producer with an optional-service poll; repeated expiry is cost, not a missing signal by itself",
            .timeout_hotspot => "inspect the producer for this finite wait and decide whether the repeated expiry is intentional polling or work that never arrives",
            .lost_wakeup_candidate => "find the missing signal or broadcast and its owner before changing the timeout or wake policy",
            .pending_producer => "find the producer or completion that should signal this still-active wait; do not synthesize readiness",
            .unsignalled_condition => "find the signal/broadcast owner for this active condition; the ledger has no notification evidence",
            .mixed_timeout_signal => "inspect signal ordering and the condition owner for a race or an intentionally periodic wait",
            .healthy => "signals or completions have been observed; retain as context rather than treating this site as the blocker",
        };
    }

    pub fn isActionable(self: Classification) bool {
        return switch (self) {
            .lost_wakeup_candidate, .pending_producer, .unsignalled_condition => true,
            else => false,
        };
    }

    pub fn isCostHotspot(self: Classification) bool {
        return switch (self) {
            .periodic_timeout_poll, .timeout_hotspot, .mixed_timeout_signal => true,
            else => false,
        };
    }
};

pub const Site = struct {
    key: u64 = 0,
    kind: WaitKind = .condition,
    waits: u64 = 0,
    active: u64 = 0,
    signaled: u64 = 0,
    timed_out: u64 = 0,
    immediate: u64 = 0,
    unknown: u64 = 0,
    aborted: u64 = 0,
    signals: u64 = 0,
    first_step: u64 = 0,
    last_step: u64 = 0,
    first_ticks: u64 = 0,
    last_ticks: u64 = 0,
    last_signal_step: u64 = 0,
    last_signal_thread_handle: u64 = 0,
    last_signal_rip: u64 = 0,
    last_timeout_step: u64 = 0,
    total_ticks: u64 = 0,
    timed_out_ticks: u64 = 0,
    max_ticks: u64 = 0,
    max_timeout_overshoot_ticks: u64 = 0,
    last_timeout_milliseconds: u64 = 0,
    /// A report may be emitted at every heartbeat, but the forensic action
    /// behind an actionable site should happen once per condition episode.
    /// These latches keep a long run from paying for (or drowning in) the
    /// same escalation while leaving the aggregate counters intact.
    unsignalled_escalation_emitted: bool = false,
    timeout_hotspot_escalation_emitted: bool = false,

    pub fn claimUnsignalledEscalation(self: *Site) bool {
        if (self.unsignalled_escalation_emitted) return false;
        self.unsignalled_escalation_emitted = true;
        return true;
    }

    pub fn claimTimeoutHotspotEscalation(self: *Site) bool {
        if (self.timeout_hotspot_escalation_emitted) return false;
        self.timeout_hotspot_escalation_emitted = true;
        return true;
    }
};

fn percent(part: u64, total: u64) u8 {
    if (total == 0) return 0;
    return @intCast(@min(@as(u64, 100), (part *| 100) / total));
}

/// Classify one completed/active wait site.  The thresholds are intentionally
/// conservative: at least eight observations and an 80% timeout share are
/// required before a site is called a timeout hotspot, so one slow startup
/// wait cannot masquerade as a polling loop.
pub fn classify(site: Site) Classification {
    if (site.waits == 0) {
        return if (site.active != 0) .pending_producer else .no_data;
    }

    const timeout_percent = percent(site.timed_out, site.waits);
    const timeout_dominates = site.timed_out >= 8 and timeout_percent >= 80;
    switch (site.kind) {
        .deadline => return .expected_deadline,
        .timed_condition => {
            if (timeout_dominates and site.last_timeout_milliseconds != 0 and
                site.last_timeout_milliseconds <= 2_000)
            {
                return .periodic_timeout_poll;
            }
            if (site.active != 0 and site.signals == 0 and site.timed_out == 0) {
                return .unsignalled_condition;
            }
            if (site.signals == 0 and site.timed_out != 0) {
                return .lost_wakeup_candidate;
            }
            if (site.timed_out != 0 and site.signaled != 0) {
                return .mixed_timeout_signal;
            }
            return if (site.active != 0) .pending_producer else .healthy;
        },
        .finite_handle, .multiple => {
            if (timeout_dominates) return .timeout_hotspot;
            if (site.active != 0 and site.signaled == 0) return .pending_producer;
            return .healthy;
        },
        .condition => {
            if (site.active != 0 and site.signals == 0) return .unsignalled_condition;
            if (site.active != 0 and site.signaled == 0) return .pending_producer;
            return .healthy;
        },
        .infinite_handle, .srw_lock => {
            if (site.active != 0 and site.signaled == 0) return .pending_producer;
            return .healthy;
        },
    }
}

/// Return the bounded site for a key/kind without exposing the mutable search
/// implementation.  Blocked-thread reporting uses this to attach producer
/// evidence to the live wait rather than guessing from the object type alone.
pub fn siteAt(self: *const Ledger, key: u64, kind: WaitKind) ?*const Site {
    const index = self.find(key, kind) orelse return null;
    return &self.sites[index];
}

pub const Ledger = struct {
    /// A title normally has only a handful of synchronization sites.  The
    /// larger bound keeps diagnostics useful for a library-heavy image while
    /// remaining a fixed-size field in `ElfState`.
    pub const capacity: usize = 96;

    sites: [capacity]Site = [_]Site{.{}} ** capacity,
    count: usize = 0,
    dropped_sites: u64 = 0,
    dropped_events: u64 = 0,
    unmatched_signals: u64 = 0,

    fn find(self: *const Ledger, key: u64, kind: WaitKind) ?usize {
        for (self.sites[0..self.count], 0..) |site, index| {
            if (site.key == key and site.kind == kind) return index;
        }
        return null;
    }

    fn findKey(self: *const Ledger, key: u64) ?usize {
        for (self.sites[0..self.count], 0..) |site, index| {
            if (site.key == key) return index;
        }
        return null;
    }

    /// Begin one bounded wait.  The returned value is one-based so zero can
    /// mean that the site table was full without adding an optional field to
    /// every guest thread.
    pub fn begin(
        self: *Ledger,
        key: u64,
        kind: WaitKind,
        step: u64,
        ticks: u64,
        timeout_milliseconds: u64,
    ) u8 {
        const index = self.find(key, kind) orelse blk: {
            if (self.count == self.sites.len) {
                self.dropped_sites +|= 1;
                self.dropped_events +|= 1;
                break :blk null;
            }
            const new_index = self.count;
            self.sites[new_index] = .{ .key = key, .kind = kind };
            self.count += 1;
            break :blk new_index;
        };
        const site_index = index orelse return 0;
        const site = &self.sites[site_index];
        // A condition that was resolved and later waited on again is a new
        // episode.  Reset only the liveness escalation; the timeout-hotspot
        // latch is intentionally run-wide because a polling site can close
        // and reopen between every expiry.
        if (site.active == 0 and (kind == .condition or kind == .timed_condition)) {
            site.unsignalled_escalation_emitted = false;
        }
        const first_observation = site.waits == 0;
        site.waits +|= 1;
        site.active +|= 1;
        if (first_observation) {
            site.first_step = step;
            site.first_ticks = ticks;
        }
        site.last_step = step;
        site.last_ticks = ticks;
        site.last_timeout_milliseconds = timeout_milliseconds;
        return @intCast(site_index + 1);
    }

    /// Record a producer-side notification.  An unmatched notification is
    /// still useful evidence: it means the signal happened outside the
    /// bounded wait sample or before the waiter registered.
    pub fn signal(self: *Ledger, key: u64, step: u64, _: u64, evidence: SignalEvidence) void {
        const index = self.findKey(key) orelse {
            self.unmatched_signals +|= 1;
            return;
        };
        const site = &self.sites[index];
        site.signals +|= 1;
        site.last_signal_step = step;
        site.last_signal_thread_handle = evidence.thread_handle;
        site.last_signal_rip = evidence.rip;
    }

    pub fn end(
        self: *Ledger,
        site_plus_one: u8,
        outcome: Outcome,
        start_step: u64,
        start_ticks: u64,
        end_step: u64,
        end_ticks: u64,
        deadline: u64,
    ) void {
        if (site_plus_one == 0) return;
        const site_index = @as(usize, site_plus_one) - 1;
        if (site_index >= self.count) return;
        const site = &self.sites[site_index];
        if (site.active != 0) site.active -= 1;
        const elapsed = end_ticks -| start_ticks;
        site.total_ticks +|= elapsed;
        site.max_ticks = @max(site.max_ticks, elapsed);
        site.last_step = end_step;
        site.last_ticks = end_ticks;
        _ = start_step;
        switch (outcome) {
            .signaled => site.signaled +|= 1,
            .timed_out => {
                site.timed_out +|= 1;
                site.timed_out_ticks +|= elapsed;
                site.last_timeout_step = end_step;
                if (deadline != 0 and end_ticks > deadline) {
                    site.max_timeout_overshoot_ticks = @max(site.max_timeout_overshoot_ticks, end_ticks - deadline);
                }
            },
            .immediate => site.immediate +|= 1,
            .unknown => site.unknown +|= 1,
            .aborted => site.aborted +|= 1,
        }
    }
};

test "wait cost ledger records duration, signal, and timeout overshoot" {
    var ledger: Ledger = .{};
    const token = ledger.begin(0x44, .finite_handle, 10, 100, 5);
    try std.testing.expect(token != 0);
    ledger.signal(0x44, 11, 105, .{ .thread_handle = 0x99, .rip = 0x1234 });
    ledger.end(token, .signaled, 10, 100, 12, 135, 0);
    try std.testing.expectEqual(@as(u64, 1), ledger.sites[0].signals);
    try std.testing.expectEqual(@as(u64, 0x99), ledger.sites[0].last_signal_thread_handle);
    try std.testing.expectEqual(@as(u64, 0x1234), ledger.sites[0].last_signal_rip);
    try std.testing.expectEqual(@as(u64, 1), ledger.sites[0].signaled);
    try std.testing.expectEqual(@as(u64, 35), ledger.sites[0].total_ticks);
    try std.testing.expectEqual(@as(u64, 100), ledger.sites[0].first_ticks);
    try std.testing.expectEqual(@as(u64, 135), ledger.sites[0].last_ticks);

    const timeout_token = ledger.begin(0x44, .finite_handle, 20, 200, 5);
    ledger.end(timeout_token, .timed_out, 20, 200, 24, 270, 250);
    try std.testing.expectEqual(@as(u64, 1), ledger.sites[0].timed_out);
    try std.testing.expectEqual(@as(u64, 70), ledger.sites[0].timed_out_ticks);
    try std.testing.expectEqual(@as(u64, 20), ledger.sites[0].max_timeout_overshoot_ticks);
}

test "wait cost ledger accounts for bounded-site overflow" {
    var ledger: Ledger = .{};
    for (0..Ledger.capacity) |index| {
        _ = ledger.begin(@intCast(index + 1), .finite_handle, 1, 1, 1);
    }
    const token = ledger.begin(0xFFFF, .finite_handle, 2, 2, 2);
    try std.testing.expectEqual(@as(u8, 0), token);
    try std.testing.expectEqual(Ledger.capacity, ledger.count);
    try std.testing.expectEqual(@as(u64, 1), ledger.dropped_sites);
    try std.testing.expectEqual(@as(u64, 1), ledger.dropped_events);
}

test "wait cost classification separates cadence, liveness, and healthy waits" {
    try std.testing.expectEqual(
        Classification.expected_deadline,
        classify(.{ .kind = .deadline, .waits = 100, .timed_out = 100 }),
    );
    try std.testing.expectEqual(
        Classification.periodic_timeout_poll,
        classify(.{ .kind = .timed_condition, .waits = 100, .timed_out = 99, .last_timeout_milliseconds = 500 }),
    );
    try std.testing.expectEqual(
        Classification.lost_wakeup_candidate,
        classify(.{ .kind = .timed_condition, .waits = 9, .timed_out = 8, .active = 1, .last_timeout_milliseconds = 5_000 }),
    );
    try std.testing.expectEqual(
        Classification.timeout_hotspot,
        classify(.{ .kind = .finite_handle, .waits = 20, .timed_out = 19, .last_timeout_milliseconds = 2 }),
    );
    try std.testing.expectEqual(
        Classification.unsignalled_condition,
        classify(.{ .kind = .condition, .waits = 1, .active = 1 }),
    );
    try std.testing.expectEqual(
        Classification.pending_producer,
        classify(.{ .kind = .infinite_handle, .waits = 1, .active = 1 }),
    );
    try std.testing.expectEqual(
        Classification.healthy,
        classify(.{ .kind = .condition, .waits = 1, .signaled = 1, .signals = 1 }),
    );
}

test "wait cost escalations are one-shot and condition episodes can rearm" {
    var ledger: Ledger = .{};
    const first = ledger.begin(0x55, .condition, 10, 10, 0);
    try std.testing.expectEqual(@as(u8, 1), first);
    try std.testing.expect(ledger.sites[0].claimUnsignalledEscalation());
    try std.testing.expect(!ledger.sites[0].claimUnsignalledEscalation());

    ledger.end(first, .signaled, 10, 10, 11, 11, 0);
    const second = ledger.begin(0x55, .condition, 20, 20, 0);
    try std.testing.expectEqual(@as(u8, 1), second);
    try std.testing.expect(ledger.sites[0].claimUnsignalledEscalation());

    const timeout = ledger.begin(0x66, .finite_handle, 30, 30, 2);
    ledger.end(timeout, .timed_out, 30, 30, 31, 31, 32);
    try std.testing.expect(ledger.sites[1].claimTimeoutHotspotEscalation());
    try std.testing.expect(!ledger.sites[1].claimTimeoutHotspotEscalation());
}
