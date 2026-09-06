//! How long a guest timeout actually takes, against how long the guest asked
//! for — and which of the three clocks in the stack is responsible for the
//! difference.
//!
//! ## The question nothing could answer
//!
//! A run contains this, and it is a complete statement of a problem nobody
//! could act on:
//!
//! ```text
//! wait policy object=0x40004bf4 kind=guest_manual_reset_event
//!   timeout_class=bounded_poll timeout_ms=30 waits=4 timeouts=4 signals=0
//! ```
//!
//! Four bounded polls, four timeouts, no signal. Read as written it says the
//! producer never signalled. But the guest asked for thirty milliseconds *of
//! guest time*, and under translation guest time can run two hundred times
//! slower than the wall — so those four polls may have covered twenty-four
//! seconds of real time, or they may have covered a hundred milliseconds and
//! given the producer no chance at all. Those are opposite findings and the
//! line supports both.
//!
//! ## Three clocks, and the one that is wrong
//!
//! * The **host timer** — measured directly by the capability probe. On the
//!   machine this was written for it overshoots a one-millisecond deadline by
//!   about half a millisecond, so it is not the problem.
//! * The **emulated guest clock** — what the guest reads, and what its timeout
//!   is denominated in.
//! * The **wall clock** — what the producer on the other end of the handshake
//!   is actually living in.
//!
//! A timeout is only meaningful when all three are related, and the ratio
//! between the guest's request and the wall time it consumed is the number that
//! relates them. This module keeps that ratio, and reports which clock the
//! discrepancy belongs to so the finding lands on the right layer.
//!
//! ## What it never does
//!
//! It does not adjust a timeout. Stretching or shrinking a guest deadline to
//! make a handshake work would make the run depend on a number Rosette chose,
//! and the next failure would be attributed to the guest.

const std = @import("std");

/// What the ratio between requested and observed says.
pub const Verdict = enum(u8) {
    /// Not enough timeouts observed to say anything.
    insufficient,
    /// The timeout consumed about as much wall time as it asked for. Whatever
    /// it is waiting on had a fair chance to arrive.
    faithful,
    /// The timeout consumed far more wall time than it asked for. Every
    /// bounded poll built on it retries far less often than the guest intended,
    /// and a handshake that needs several attempts gets one.
    dilated,
    /// The timeout consumed far less wall time than it asked for. The guest
    /// believes it waited and it did not, so a producer that was about to
    /// signal never got the chance — and the guest concludes the producer is
    /// dead.
    compressed,

    pub fn label(self: Verdict) []const u8 {
        return switch (self) {
            .insufficient => "insufficient",
            .faithful => "faithful",
            .dilated => "DILATED",
            .compressed => "COMPRESSED",
        };
    }

    pub fn actionable(self: Verdict) bool {
        return self == .dilated or self == .compressed;
    }

    pub fn describe(self: Verdict) []const u8 {
        return switch (self) {
            .insufficient => "too few timeouts have been observed to relate the guest's deadline to real time; a timeout verdict here is not supportable either way",
            .faithful => "guest deadlines are consuming about the wall time they ask for, so a poll that expired had a fair chance and its expiry is evidence about the producer rather than about the clock",
            .dilated => "a guest deadline is consuming far more wall time than it asks for. A bounded poll written to retry many times retries a few, and a handshake that needs several attempts to complete gets one — which reads as a producer that never signalled and is not",
            .compressed => "a guest deadline is expiring in far less wall time than it asks for. The guest believes it waited and did not, so anything that was about to signal never had the chance and the guest concludes it is dead",
        };
    }
};

/// Ratios beyond which the relationship is a finding rather than jitter.
/// Deliberately wide: the point is not to hold the clocks to a standard but to
/// notice when one of them is in a different regime from the code that assumes
/// it.
pub const dilated_above_percent: u64 = 400;
pub const compressed_below_percent: u64 = 25;

/// Where the discrepancy lives, so the finding lands on the right layer.
pub const Attribution = enum(u8) {
    unknown,
    /// The host's own timer overshoot accounts for it. A finding about the
    /// machine, and the capability probe already measured it.
    host_timer,
    /// The host timer is accurate and the guest's clock is not running at the
    /// rate the guest's code assumes. A finding about the emulated clock, which
    /// is where a translated run's timing almost always goes wrong.
    emulated_clock,

    pub fn label(self: Attribution) []const u8 {
        return switch (self) {
            .unknown => "unknown",
            .host_timer => "host:timer",
            .emulated_clock => "emulator:clock",
        };
    }
};

pub const Ledger = struct {
    samples: u64 = 0,
    /// Guest milliseconds requested, summed.
    requested_ms_total: u64 = 0,
    /// Wall milliseconds consumed, summed.
    observed_ms_total: u64 = 0,
    /// The largest single discrepancy, kept with its request so a report can
    /// name a concrete wait rather than an average.
    worst_requested_ms: u64 = 0,
    worst_observed_ms: u64 = 0,
    worst_object: u64 = 0,
    /// The host timer's own measured overshoot, in microseconds, from the
    /// capability probe. Supplied rather than assumed: without it the ledger
    /// cannot tell a slow machine from a slow emulated clock.
    host_overshoot_us: u64 = 0,
    host_overshoot_known: bool = false,

    /// A guest wait that reached its deadline, with the wall time it consumed.
    ///
    /// Only expired waits are offered. A wait that was signalled early says
    /// nothing about the deadline, and averaging it in would pull every ratio
    /// toward one and hide the finding.
    pub fn observeExpiry(
        self: *Ledger,
        object: u64,
        requested_ms: u64,
        observed_ms: u64,
    ) void {
        if (requested_ms == 0) return;
        self.samples +|= 1;
        self.requested_ms_total +|= requested_ms;
        self.observed_ms_total +|= observed_ms;

        const ratio = percentOf(requested_ms, observed_ms);
        const worst_ratio = if (self.worst_requested_ms == 0)
            100
        else
            percentOf(self.worst_requested_ms, self.worst_observed_ms);
        const worse = distanceFromFaithful(ratio) > distanceFromFaithful(worst_ratio);
        if (self.worst_requested_ms == 0 or worse) {
            self.worst_requested_ms = requested_ms;
            self.worst_observed_ms = observed_ms;
            self.worst_object = object;
        }
    }

    pub fn noteHostOvershoot(self: *Ledger, microseconds: u64) void {
        self.host_overshoot_us = microseconds;
        self.host_overshoot_known = true;
    }

    /// Observed wall time as a percentage of what the guest asked for.
    /// One hundred means the deadline was honoured.
    pub fn ratioPercent(self: *const Ledger) u64 {
        return percentOf(self.requested_ms_total, self.observed_ms_total);
    }

    pub fn verdict(self: *const Ledger) Verdict {
        if (self.samples < 2 or self.requested_ms_total == 0) return .insufficient;
        const ratio = self.ratioPercent();
        if (ratio > dilated_above_percent) return .dilated;
        if (ratio < compressed_below_percent) return .compressed;
        return .faithful;
    }

    /// Which clock the discrepancy belongs to.
    ///
    /// The host timer can only ever *add* time, and only as much as it was
    /// measured to add. When the discrepancy is larger than the host's own
    /// overshoot could account for across every sample, it is the emulated
    /// clock — and that is a different team's problem from a slow machine.
    pub fn attribution(self: *const Ledger) Attribution {
        if (!self.host_overshoot_known) return .unknown;
        const found = self.verdict();
        if (found == .compressed) return .emulated_clock;
        if (found != .dilated) return .unknown;
        const host_added_ms = (self.host_overshoot_us *| self.samples) / 1000;
        const excess_ms = self.observed_ms_total -| self.requested_ms_total;
        return if (host_added_ms >= excess_ms) .host_timer else .emulated_clock;
    }
};

fn percentOf(requested: u64, observed: u64) u64 {
    if (requested == 0) return 0;
    return (observed *| 100) / requested;
}

fn distanceFromFaithful(percent: u64) u64 {
    return if (percent > 100) percent - 100 else 100 - percent;
}

test "an empty ledger says nothing" {
    const ledger = Ledger{};
    try std.testing.expectEqual(Verdict.insufficient, ledger.verdict());
    try std.testing.expectEqual(Attribution.unknown, ledger.attribution());
}

test "one sample is not enough to relate the clocks" {
    var ledger = Ledger{};
    ledger.observeExpiry(0x40004bf4, 30, 6_000);
    try std.testing.expectEqual(Verdict.insufficient, ledger.verdict());
}

// The reading this was written for: four bounded polls with a thirty
// millisecond guest deadline, each consuming six seconds of wall clock.
test "a guest deadline consuming two hundred times its request is dilated" {
    var ledger = Ledger{};
    var index: usize = 0;
    while (index < 4) : (index += 1) {
        ledger.observeExpiry(0x40004bf4, 30, 6_000);
    }
    try std.testing.expectEqual(Verdict.dilated, ledger.verdict());
    try std.testing.expectEqual(@as(u64, 20_000), ledger.ratioPercent());
    try std.testing.expectEqual(@as(u64, 0x40004bf4), ledger.worst_object);
    try std.testing.expect(ledger.verdict().actionable());
}

// The host timer can only add as much as it was measured to add. Anything
// beyond that belongs to the emulated clock, and the two call for opposite work.
test "a dilation larger than the host timer can explain is the emulated clock" {
    var ledger = Ledger{};
    ledger.noteHostOvershoot(509);
    var index: usize = 0;
    while (index < 4) : (index += 1) {
        ledger.observeExpiry(0x40004bf4, 30, 6_000);
    }
    try std.testing.expectEqual(Attribution.emulated_clock, ledger.attribution());
}

test "a dilation the host timer accounts for is the host's" {
    var ledger = Ledger{};
    // A machine whose timed waits overshoot by twenty milliseconds.
    ledger.noteHostOvershoot(20_000);
    var index: usize = 0;
    while (index < 4) : (index += 1) {
        ledger.observeExpiry(0x1000, 1, 21);
    }
    try std.testing.expectEqual(Verdict.dilated, ledger.verdict());
    try std.testing.expectEqual(Attribution.host_timer, ledger.attribution());
}

// The opposite failure, and the more dangerous one: the guest believes it
// waited and did not, so nothing had a chance to signal.
test "a deadline expiring far early is compressed" {
    var ledger = Ledger{};
    ledger.noteHostOvershoot(509);
    ledger.observeExpiry(0x2000, 100, 5);
    ledger.observeExpiry(0x2000, 100, 5);
    try std.testing.expectEqual(Verdict.compressed, ledger.verdict());
    try std.testing.expectEqual(Attribution.emulated_clock, ledger.attribution());
}

test "a faithful deadline is not a finding" {
    var ledger = Ledger{};
    ledger.noteHostOvershoot(509);
    ledger.observeExpiry(0x3000, 30, 31);
    ledger.observeExpiry(0x3000, 30, 32);
    try std.testing.expectEqual(Verdict.faithful, ledger.verdict());
    try std.testing.expect(!ledger.verdict().actionable());
}

// A wait that was signalled early says nothing about its deadline, and
// averaging it in would pull every ratio toward one and hide the finding.
test "a zero request is not a sample" {
    var ledger = Ledger{};
    ledger.observeExpiry(0x4000, 0, 5);
    try std.testing.expectEqual(@as(u64, 0), ledger.samples);
}

test "the worst discrepancy is retained with its object" {
    var ledger = Ledger{};
    ledger.observeExpiry(0x1000, 30, 31);
    ledger.observeExpiry(0x2000, 30, 9_000);
    ledger.observeExpiry(0x3000, 30, 33);
    try std.testing.expectEqual(@as(u64, 0x2000), ledger.worst_object);
    try std.testing.expectEqual(@as(u64, 9_000), ledger.worst_observed_ms);
}
