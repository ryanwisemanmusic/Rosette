//! Whether a run stopped because the guest stopped, or because the run did.
//!
//! Every stall verdict in this subsystem is built on "X has not happened".
//! That phrasing hides a variable nobody was tracking: *how much of the guest's
//! own timeline the run actually covered*. A title that reaches a milestone at
//! 94% of the way through a run has not stalled. It ran out of wall clock.
//!
//! The run this was written against makes the point exactly. 830 seconds of
//! host time bought **4,085 milliseconds** of emulated time — about 203 seconds
//! of wall clock per emulated second. The last GPU milestone, the title
//! registering its graphics interrupt callback, landed at emulated 3,827 ms:
//! 93.7% of the way through everything the run ever saw. `VdInitializeRingBuffer`
//! comes after that in the bring-up order, and the run ended 258 emulated
//! milliseconds later. Every report called this a stall. It was a horizon.
//!
//! The distinction is not academic — it decides what to do next, and the two
//! answers are opposites:
//!
//!   * **horizon** — run longer. Nothing is wrong. The projection below says
//!     how much longer.
//!   * **stalled** — running longer changes nothing. Debug.
//!
//! Getting this wrong costs weeks, because a horizon misread as a stall sends
//! you looking for a defect that is not there, in a subsystem that is working.
//!
//! ## What makes a stall a stall
//!
//! Two independent conditions, and both are required:
//!
//!   1. No *new* milestone for a long stretch of the run. A milestone is any
//!      first-time arrival at a named boundary — not a counter ticking, which a
//!      spin loop also does.
//!   2. An independent progress axis is frozen. Supplied by the caller, because
//!      the axes that count differ by subsystem, and a predictor that decides
//!      this for itself is how a busy-but-quiet run gets called dead.
//!
//! Neither alone is sufficient. A run can be quiet because it is between
//! milestones, and a frozen axis late in a run that is still reaching
//! milestones is a bottleneck rather than a stop.

const std = @import("std");

/// Emulated time is the guest's own clock. Host time is the wall clock. The
/// ratio between them is the single number that decides whether a run of a
/// given length could ever have reached a given milestone, and until this
/// module existed nothing in Rosette knew either quantity.
pub const Sample = struct {
    /// Guest instructions executed.
    step: u64 = 0,
    /// The guest's own elapsed time, in milliseconds. Recovered from the
    /// emulator's vblank reporting, which is the only clock the title itself
    /// can be said to observe.
    emulated_ms: u64 = 0,
    /// Vblanks the emulator has issued. Kept separately from `emulated_ms`
    /// because a run can tick vblanks while its millisecond clock is stopped,
    /// and the disagreement is worth seeing.
    vblanks: u64 = 0,
    /// Host wall-clock seconds elapsed.
    host_seconds: u64 = 0,
};

pub const Verdict = enum(u8) {
    /// No milestone has ever been reached. Nothing can be said about pacing.
    not_started,
    /// The most recent milestone landed inside the final stretch of the run.
    /// The guest was still advancing when the run ended: this is a horizon and
    /// not a stall, and the only correct response is a longer run.
    horizon,
    /// Milestones stopped a while ago, but no independent axis has frozen. The
    /// run is between milestones; neither "stalled" nor "fine" is supportable.
    quiet,
    /// Milestones stopped long ago and an independent progress axis is frozen.
    /// A longer run will not help.
    stalled,

    pub fn label(self: Verdict) []const u8 {
        return switch (self) {
            .not_started => "not-started",
            .horizon => "HORIZON",
            .quiet => "quiet",
            .stalled => "STALLED",
        };
    }

    /// True when running for longer is the correct next action.
    pub fn wantsLongerRun(self: Verdict) bool {
        return self == .horizon or self == .quiet;
    }

    pub fn guidance(self: Verdict) []const u8 {
        return switch (self) {
            .not_started => "no milestone was ever reached, so the run says nothing about pacing. Check that the guest started at all before reading any stall verdict",
            .horizon => "the newest milestone landed in the final stretch of the run: the guest was still advancing when the run ended. This is a horizon, not a stall — every downstream 'never happened' below is a statement about run length. Run longer before changing anything",
            .quiet => "no new milestone for a while, and the quiet tail is not yet a large enough share of the run for a stall verdict. Read `axis_frozen` on the same line before deciding what this is: a frozen axis under a short tail is a run that may be about to stall, and a moving axis is a run between milestones. Neither is a clean bill of health",
            .stalled => "milestones stopped long ago and an independent progress axis is frozen. A longer run will not help; this is the case where debugging is the right response",
        };
    }
};

/// The fraction of the run that may pass without a new milestone before the
/// run stops counting as "still advancing". A tenth is deliberately generous:
/// the cost of calling a horizon a stall is weeks, and the cost of calling a
/// stall a horizon is one more run.
pub const horizon_tail_fraction: u64 = 10;

/// How much of the run must be quiet before a frozen axis is allowed to make
/// the verdict `stalled`. Below this the run has simply not been quiet long
/// enough for the frozen axis to mean anything.
pub const stall_tail_fraction: u64 = 2;

pub const max_milestones: usize = 24;

pub const Milestone = struct {
    name: []const u8 = "",
    step: u64 = 0,
    emulated_ms: u64 = 0,
    vblanks: u64 = 0,
};

pub const Projection = struct {
    /// Emulated milliseconds per host second. Zero when the run produced no
    /// host time or no emulated time to measure against.
    emulated_ms_per_host_second: u64 = 0,
    /// Host seconds needed to reach a requested emulated deadline, at the rate
    /// this run actually achieved. Null when the rate is unknown.
    host_seconds_required: ?u64 = null,
    /// The emulated deadline the projection was made against.
    target_emulated_ms: u64 = 0,

    pub fn known(self: Projection) bool {
        return self.emulated_ms_per_host_second != 0;
    }
};

pub const Ledger = struct {
    first: Sample = .{},
    latest: Sample = .{},
    started: bool = false,

    milestones: [max_milestones]Milestone = [_]Milestone{.{}} ** max_milestones,
    milestone_count: usize = 0,
    /// Milestones past the retained window. Counted so the list is never
    /// mistaken for the whole history.
    milestones_dropped: u64 = 0,

    /// The newest milestone's position, retained separately from the list so a
    /// dropped tail still leaves the verdict correct.
    last_milestone_step: u64 = 0,
    last_milestone_emulated_ms: u64 = 0,
    last_milestone_name: []const u8 = "",
    milestones_reached: u64 = 0,

    pub fn observe(self: *Ledger, sample: Sample) void {
        if (!self.started) {
            self.first = sample;
            self.started = true;
        }
        // Monotonic by construction: a sample that goes backwards is a
        // reporting artefact, and letting it shorten the run would make the
        // tail fraction — and therefore the verdict — swing on noise.
        if (sample.step > self.latest.step) self.latest.step = sample.step;
        if (sample.emulated_ms > self.latest.emulated_ms) self.latest.emulated_ms = sample.emulated_ms;
        if (sample.vblanks > self.latest.vblanks) self.latest.vblanks = sample.vblanks;
        if (sample.host_seconds > self.latest.host_seconds) self.latest.host_seconds = sample.host_seconds;
    }

    /// Record a first-time arrival at a named boundary.
    ///
    /// Deliberately not a counter. A spin loop advances counters; only real
    /// progress reaches somewhere it has never been. Callers must filter to
    /// first arrivals, which every contract in this subsystem already tracks.
    pub fn noteMilestone(self: *Ledger, name: []const u8) void {
        self.milestones_reached +|= 1;
        self.last_milestone_step = self.latest.step;
        self.last_milestone_emulated_ms = self.latest.emulated_ms;
        self.last_milestone_name = name;
        if (self.milestone_count == max_milestones) {
            self.milestones_dropped +|= 1;
            return;
        }
        self.milestones[self.milestone_count] = .{
            .name = name,
            .step = self.latest.step,
            .emulated_ms = self.latest.emulated_ms,
            .vblanks = self.latest.vblanks,
        };
        self.milestone_count += 1;
    }

    /// Steps elapsed since the newest milestone.
    pub fn quietSteps(self: *const Ledger) u64 {
        return self.latest.step -| self.last_milestone_step;
    }

    /// The quiet tail as a percentage of the whole run. This is the number the
    /// verdict turns on: it is scale-free, so a two-minute run and a two-hour
    /// run are judged the same way.
    pub fn quietTailPercent(self: *const Ledger) u64 {
        if (self.latest.step == 0) return 0;
        return (self.quietSteps() *| 100) / self.latest.step;
    }

    /// How far through the run the newest milestone landed, as a percentage.
    pub fn progressPercent(self: *const Ledger) u64 {
        if (self.latest.step == 0) return 0;
        return (self.last_milestone_step *| 100) / self.latest.step;
    }

    pub fn verdict(self: *const Ledger, independent_axis_frozen: bool) Verdict {
        if (self.milestones_reached == 0) return .not_started;
        const tail = self.quietTailPercent();
        if (tail < 100 / horizon_tail_fraction) return .horizon;
        if (independent_axis_frozen and tail >= 100 / stall_tail_fraction) return .stalled;
        return .quiet;
    }

    /// Emulated milliseconds the run achieved per host second.
    pub fn emulatedMsPerHostSecond(self: *const Ledger) u64 {
        const host = self.latest.host_seconds -| self.first.host_seconds;
        if (host == 0) return 0;
        const emulated = self.latest.emulated_ms -| self.first.emulated_ms;
        return emulated / host;
    }

    /// How much host time reaching a given emulated deadline would take, at
    /// the rate this run actually achieved.
    ///
    /// This is the number that turns "run longer" from advice into a decision.
    /// A projection of four minutes is a different conversation from one of
    /// nine hours, and until it is on the page the choice is being made blind.
    pub fn project(self: *const Ledger, target_emulated_ms: u64) Projection {
        const rate = self.emulatedMsPerHostSecond();
        var result = Projection{
            .emulated_ms_per_host_second = rate,
            .target_emulated_ms = target_emulated_ms,
        };
        if (rate == 0) return result;
        const remaining = target_emulated_ms -| self.latest.emulated_ms;
        result.host_seconds_required = (remaining + rate - 1) / rate;
        return result;
    }
};

test "a milestone in the final stretch is a horizon, not a stall" {
    // The live reading: the last milestone at 93.7% of the run, with the
    // producer's own counters flat afterwards. Every existing verdict called
    // this a stall.
    var ledger = Ledger{};
    ledger.observe(.{ .step = 0, .emulated_ms = 0, .host_seconds = 0 });
    ledger.observe(.{ .step = 5_007_000_000, .emulated_ms = 3_827, .vblanks = 225, .host_seconds = 778 });
    ledger.noteMilestone("VdSetGraphicsInterruptCallback");
    ledger.observe(.{ .step = 5_342_943_476, .emulated_ms = 4_085, .vblanks = 240, .host_seconds = 830 });

    try std.testing.expectEqual(@as(u64, 93), ledger.progressPercent());
    try std.testing.expectEqual(@as(u64, 6), ledger.quietTailPercent());
    // A frozen axis must not override a run that was still advancing.
    try std.testing.expectEqual(Verdict.horizon, ledger.verdict(true));
    try std.testing.expectEqual(Verdict.horizon, ledger.verdict(false));
    try std.testing.expect(ledger.verdict(true).wantsLongerRun());
}

test "a long quiet tail with a frozen axis is a stall" {
    var ledger = Ledger{};
    ledger.observe(.{ .step = 0, .host_seconds = 0 });
    ledger.observe(.{ .step = 100_000_000, .emulated_ms = 500, .host_seconds = 20 });
    ledger.noteMilestone("ring buffer initialised");
    ledger.observe(.{ .step = 5_000_000_000, .emulated_ms = 900, .host_seconds = 830 });

    try std.testing.expectEqual(@as(u64, 98), ledger.quietTailPercent());
    try std.testing.expectEqual(Verdict.stalled, ledger.verdict(true));
    // The same tail without a frozen axis is not enough to convict.
    try std.testing.expectEqual(Verdict.quiet, ledger.verdict(false));
    try std.testing.expect(!ledger.verdict(true).wantsLongerRun());
    try std.testing.expect(ledger.verdict(false).wantsLongerRun());
}

test "a run that reached nothing says nothing about pacing" {
    var ledger = Ledger{};
    ledger.observe(.{ .step = 5_000_000_000, .emulated_ms = 4_000, .host_seconds = 830 });
    try std.testing.expectEqual(Verdict.not_started, ledger.verdict(true));
    try std.testing.expectEqual(Verdict.not_started, ledger.verdict(false));
    try std.testing.expectEqual(@as(u64, 0), ledger.milestones_reached);
}

test "the projection turns run longer into a decision" {
    var ledger = Ledger{};
    ledger.observe(.{ .step = 0, .emulated_ms = 0, .host_seconds = 0 });
    ledger.observe(.{ .step = 5_342_943_476, .emulated_ms = 4_085, .host_seconds = 830 });
    ledger.noteMilestone("VdSetGraphicsInterruptCallback");

    // 4,085 emulated ms in 830 host seconds is 4 ms of guest time per second
    // of wall clock.
    try std.testing.expectEqual(@as(u64, 4), ledger.emulatedMsPerHostSecond());

    // Reaching ten emulated seconds needs about another 1,479 seconds.
    const projection = ledger.project(10_000);
    try std.testing.expect(projection.known());
    try std.testing.expectEqual(@as(u64, 1_479), projection.host_seconds_required.?);

    // A deadline already passed needs no further time.
    const reached = ledger.project(1_000);
    try std.testing.expectEqual(@as(u64, 0), reached.host_seconds_required.?);
}

test "an unmeasurable rate is reported as unknown rather than as zero work" {
    var ledger = Ledger{};
    ledger.observe(.{ .step = 1_000, .emulated_ms = 0, .host_seconds = 0 });
    ledger.noteMilestone("something");
    const projection = ledger.project(10_000);
    try std.testing.expect(!projection.known());
    try std.testing.expect(projection.host_seconds_required == null);
}

test "samples never shorten the run" {
    // A reporting artefact that walks a sample backwards would shrink the
    // denominator and swing the verdict on noise.
    var ledger = Ledger{};
    ledger.observe(.{ .step = 1_000_000, .emulated_ms = 500, .vblanks = 30, .host_seconds = 100 });
    ledger.noteMilestone("first");
    ledger.observe(.{ .step = 10_000_000, .emulated_ms = 4_000, .vblanks = 240, .host_seconds = 800 });
    ledger.observe(.{ .step = 5_000, .emulated_ms = 1, .vblanks = 0, .host_seconds = 1 });

    try std.testing.expectEqual(@as(u64, 10_000_000), ledger.latest.step);
    try std.testing.expectEqual(@as(u64, 4_000), ledger.latest.emulated_ms);
    try std.testing.expectEqual(@as(u64, 240), ledger.latest.vblanks);
    try std.testing.expectEqual(@as(u64, 800), ledger.latest.host_seconds);
}

test "the retained milestone list is bounded and the verdict is not" {
    var ledger = Ledger{};
    ledger.observe(.{ .step = 100, .host_seconds = 1 });
    var index: usize = 0;
    while (index < max_milestones + 6) : (index += 1) {
        ledger.observe(.{ .step = 100 + index, .host_seconds = 1 });
        ledger.noteMilestone("milestone");
    }
    try std.testing.expectEqual(max_milestones, ledger.milestone_count);
    try std.testing.expectEqual(@as(u64, 6), ledger.milestones_dropped);
    try std.testing.expectEqual(@as(u64, max_milestones + 6), ledger.milestones_reached);
    // The newest milestone still decides the verdict even though the list
    // stopped retaining entries long before it.
    try std.testing.expectEqual(ledger.latest.step, ledger.last_milestone_step);
    try std.testing.expectEqual(Verdict.horizon, ledger.verdict(true));
}

test "every verdict carries guidance that names the next action" {
    inline for (@typeInfo(Verdict).@"enum".fields) |field| {
        const value: Verdict = @enumFromInt(field.value);
        try std.testing.expect(value.label().len != 0);
        try std.testing.expect(value.guidance().len > 40);
    }
    try std.testing.expect(std.mem.indexOf(u8, Verdict.horizon.guidance(), "Run longer") != null);
    try std.testing.expect(std.mem.indexOf(u8, Verdict.stalled.guidance(), "will not help") != null);
}
