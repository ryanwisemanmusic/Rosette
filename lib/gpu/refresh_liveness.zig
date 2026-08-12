//! Which side of the pipeline stopped, when guest output never refreshes.
//!
//! `bootstrap` answers *where* a stalled graphics stack is stuck: the earliest
//! step not observed, and whether its precondition holds. That is the right
//! first question and it has a failure mode — once the frontier settles, the
//! answer stops changing, and a watchdog that re-reports it every vblank emits
//! thousands of identical lines that between them carry one bit of information.
//! A run can spend forty-five seconds saying "the write pointer is still zero"
//! several thousand times and never once say the thing that would end the
//! investigation.
//!
//! The thing worth saying is which side went quiet, and it is not visible in
//! the frontier at all. The frontier is a guest-side fact; a stalled pipeline
//! has *two* participants, and the counters that would separate them sit on
//! opposite sides of the boundary:
//!
//!   * **Host-originated events** happen on the host's own schedule — vblank
//!     ticks, interrupt callbacks the host initiates, presenter wakeups. They
//!     keep rising whether or not the guest is alive, which is precisely why a
//!     dead guest still looks busy.
//!   * **Guest-originated events** can only exist because guest code executed —
//!     a kernel call, an MMIO write, a ring pointer advance.
//!
//! Cross them and the ambiguity collapses. Host rising while guest is frozen is
//! not a guest that has not got there yet; it is a guest that *stopped*, and no
//! amount of waiting will change it. That is a fault to go and find, not a
//! bootstrap step to keep waiting on — and it is the diagnosis that a frontier
//! report, however detailed, structurally cannot reach.
//!
//! ## Reporting on state change, not on schedule
//!
//! The second job here is suppression. A verdict is emitted when it is *new*,
//! and afterwards only at widening dwell milestones, so a genuine stall stays
//! audible without the log filling with restatements. The milestones widen
//! rather than repeat because the useful information in "still stuck" decays:
//! the first second matters, the four hundredth does not.
//!
//! Deliberately does not act. No refresh is forced, no swap is synthesised, no
//! callback is invoked on the guest's behalf. A frame the guest did not produce
//! would replace the one honest signal in the subsystem — that it never got
//! there — with a fabricated one, and the stall would then be invisible instead
//! of merely loud.

const std = @import("std");
const bootstrap = @import("bootstrap.zig");

/// One reading of the pipeline, taken whenever the caller already samples it —
/// typically per vblank. Cheap enough to take at that rate, and the monitor
/// exists so that taking it often does not mean reporting it often.
pub const Sample = struct {
    now_ms: u64 = 0,
    /// The earliest bootstrap step not yet observed.
    frontier: bootstrap.Step = .initialize_engines,
    /// Whether that step was reachable — what `bootstrap` already computes.
    precondition_met: bool = false,
    /// Events that could only have happened because guest code ran: kernel
    /// calls, guest MMIO writes, ring write-pointer advances. Monotonic.
    guest_originated_events: u64 = 0,
    /// Events the host generates on its own schedule: vblank ticks, host
    /// -initiated interrupt callback dispatches, presenter wakeups. Monotonic.
    host_originated_events: u64 = 0,
    /// Refresh attempts and successes, kept apart because "never attempted" and
    /// "attempted and failed" are different faults with different owners.
    refresh_attempts: u64 = 0,
    refresh_successes: u64 = 0,
    swap_count: u64 = 0,
};

pub const Verdict = enum(u8) {
    /// The frontier moved since the last report. The only verdict that is
    /// progress, and worth emitting precisely because it is rare.
    advancing,
    /// The frontier has not moved, but not for long enough to mean anything.
    settling,
    /// The frontier's precondition is unmet: this step was never reachable, so
    /// it is a symptom and the real stall is upstream of it.
    stalled_upstream,
    /// The step is reachable, the guest has not taken it, and the guest is
    /// still producing events elsewhere. It is running and has not got here.
    awaiting_guest,
    /// Host-side events keep arriving and guest-originated events have stopped
    /// entirely. The guest is not late, it is gone: a fault, an unhandled
    /// signal, or a thread that exited. Waiting cannot resolve this one.
    producer_dead,
    /// The pipeline reports itself ready and refresh has never once been
    /// attempted. The consumer, not the producer, is the frontier.
    refresh_never_attempted,
    /// Refresh is attempted and never succeeds. The attempt path is live, so
    /// the fault is inside it rather than upstream.
    refresh_always_failing,

    pub fn isStall(self: Verdict) bool {
        return switch (self) {
            .advancing, .settling => false,
            else => true,
        };
    }

    /// A stable code for the caller to notify on, `null` when there is nothing
    /// to act on. Same contract as the zero adjudicator: a healthy pipeline
    /// should cost nothing, not merely log quietly.
    pub fn notificationCode(self: Verdict) ?u16 {
        return switch (self) {
            .advancing, .settling => null,
            .stalled_upstream => 0x6C01,
            .awaiting_guest => 0x6C02,
            .producer_dead => 0x6C03,
            .refresh_never_attempted => 0x6C04,
            .refresh_always_failing => 0x6C05,
        };
    }

    pub fn describe(self: Verdict) []const u8 {
        return switch (self) {
            .advancing => "the bootstrap frontier moved since the last report; the pipeline is making progress",
            .settling => "the frontier has not moved recently, but not for long enough to distinguish a stall from ordinary latency",
            .stalled_upstream => "this step's precondition is unmet, so it was never reachable. It is a symptom: the stall is upstream and investigating this step investigates the wrong thing",
            .awaiting_guest => "the step is reachable and the guest is still producing events elsewhere, so the guest is running and has not reached this call yet. Waiting is the correct response",
            .producer_dead => "host-side events keep arriving while guest-originated events have stopped entirely. The guest is not late, it has stopped: look for a fault, an unhandled signal, or a thread that exited. No amount of further waiting will change this",
            .refresh_never_attempted => "the pipeline reports itself ready and guest output refresh has never once been attempted, so the frontier is the consumer rather than the producer",
            .refresh_always_failing => "refresh is being attempted and never succeeds. The attempt path is live, so the fault is inside it and not upstream of it",
        };
    }
};

pub const Report = struct {
    verdict: Verdict = .settling,
    frontier: bootstrap.Step = .initialize_engines,
    /// How long the frontier has been where it is.
    dwell_ms: u64 = 0,
    /// How long since any guest-originated event, which is the measurement
    /// `producer_dead` rests on.
    guest_silence_ms: u64 = 0,
    /// Host events observed during that silence. A large number here is the
    /// evidence that the host side is fine and the guest side is not.
    host_events_during_silence: u64 = 0,

    pub fn isStall(self: Report) bool {
        return self.verdict.isStall();
    }

    pub fn notificationCode(self: Report) ?u16 {
        return self.verdict.notificationCode();
    }
};

/// How long the frontier must hold still before a stall verdict is offered at
/// all. Below this, ordinary latency and a stall are indistinguishable.
pub const default_settle_ms: u64 = 1_000;

/// How long guest-originated events must be absent, while host events keep
/// arriving, before the guest is called dead rather than slow. Generous on
/// purpose: a guest can legitimately be blocked on a host wait for a while, and
/// a false `producer_dead` would send the reader after a fault that never
/// happened.
pub const default_producer_silence_ms: u64 = 3_000;

/// Host events that must arrive during the silence before it counts. Time alone
/// is not enough — if the host is also idle, nothing is being starved and the
/// asymmetry that makes the verdict meaningful does not exist.
pub const default_host_events_required: u64 = 16;

pub const Thresholds = struct {
    settle_ms: u64 = default_settle_ms,
    producer_silence_ms: u64 = default_producer_silence_ms,
    host_events_required: u64 = default_host_events_required,
};

/// Sampled continuously, reports on change. Holds no allocation and no history
/// beyond the previous sample, so it can sit directly in the vblank path.
pub const Monitor = struct {
    thresholds: Thresholds = .{},

    started: bool = false,
    frontier: bootstrap.Step = .initialize_engines,
    frontier_since_ms: u64 = 0,
    last_guest_events: u64 = 0,
    last_guest_event_ms: u64 = 0,
    host_events_at_guest_silence: u64 = 0,

    reported: ?Verdict = null,
    reported_at_ms: u64 = 0,
    /// The dwell at which the current verdict was last emitted. Milestones
    /// widen from here, so a persistent stall is restated rarely rather than
    /// every sample.
    reported_dwell_ms: u64 = 0,

    stall_reports: u64 = 0,
    suppressed_samples: u64 = 0,

    pub fn init(thresholds: Thresholds) Monitor {
        return .{ .thresholds = thresholds };
    }

    /// Take a reading. Returns a report only when it says something the caller
    /// has not already been told, and `null` otherwise — the suppression is the
    /// feature, not an optimisation.
    pub fn observe(self: *Monitor, sample: Sample) ?Report {
        if (!self.started) {
            self.started = true;
            self.frontier = sample.frontier;
            self.frontier_since_ms = sample.now_ms;
            self.last_guest_events = sample.guest_originated_events;
            self.last_guest_event_ms = sample.now_ms;
            self.host_events_at_guest_silence = sample.host_originated_events;
        }

        if (sample.guest_originated_events != self.last_guest_events) {
            self.last_guest_events = sample.guest_originated_events;
            self.last_guest_event_ms = sample.now_ms;
            self.host_events_at_guest_silence = sample.host_originated_events;
        }

        const advanced = @intFromEnum(sample.frontier) != @intFromEnum(self.frontier);
        if (advanced) {
            self.frontier = sample.frontier;
            self.frontier_since_ms = sample.now_ms;
        }

        const dwell_ms = sample.now_ms -| self.frontier_since_ms;
        const guest_silence_ms = sample.now_ms -| self.last_guest_event_ms;
        const host_during_silence = sample.host_originated_events -| self.host_events_at_guest_silence;

        const verdict = self.decide(sample, dwell_ms, guest_silence_ms, host_during_silence);
        const report = Report{
            .verdict = verdict,
            .frontier = sample.frontier,
            .dwell_ms = dwell_ms,
            .guest_silence_ms = guest_silence_ms,
            .host_events_during_silence = host_during_silence,
        };

        if (advanced) return self.emit(report, sample.now_ms);
        if (self.reported == null or self.reported.? != verdict) return self.emit(report, sample.now_ms);
        if (dwell_ms >= nextMilestone(self.reported_dwell_ms, self.thresholds.settle_ms)) {
            return self.emit(report, sample.now_ms);
        }

        self.suppressed_samples +|= 1;
        return null;
    }

    fn decide(
        self: *const Monitor,
        sample: Sample,
        dwell_ms: u64,
        guest_silence_ms: u64,
        host_during_silence: u64,
    ) Verdict {
        if (dwell_ms == 0) return .advancing;

        // The asymmetry outranks everything else. A guest that has stopped
        // producing while the host keeps ticking cannot be waited out, so
        // classifying it as "not there yet" would be the one answer guaranteed
        // to waste the reader's time.
        if (guest_silence_ms >= self.thresholds.producer_silence_ms and
            host_during_silence >= self.thresholds.host_events_required)
        {
            return .producer_dead;
        }

        if (dwell_ms < self.thresholds.settle_ms) return .settling;

        if (!sample.precondition_met) return .stalled_upstream;

        // Consumer-side faults are only meaningful once the producer has got
        // far enough that a refresh was owed at all. The write-pointer step
        // itself is *not* far enough: while it is still the frontier the guest
        // has submitted nothing, so a missing refresh is the correct state and
        // reporting it would invent a second fault beside the real one.
        if (@intFromEnum(sample.frontier) > @intFromEnum(bootstrap.Step.ring_write_pointer)) {
            if (sample.refresh_attempts == 0) return .refresh_never_attempted;
            if (sample.refresh_successes == 0) return .refresh_always_failing;
        }

        return .awaiting_guest;
    }

    fn emit(self: *Monitor, report: Report, now_ms: u64) Report {
        self.reported = report.verdict;
        self.reported_at_ms = now_ms;
        self.reported_dwell_ms = report.dwell_ms;
        if (report.isStall()) self.stall_reports +|= 1;
        return report;
    }
};

/// Widening restatement schedule. The information in "still stuck" decays, so
/// the interval doubles rather than repeating: loud at first, then a background
/// note that a long run is still not finished.
///
/// The settle time is a floor, not just a starting point. Doubling from the
/// dwell at which a verdict was first adopted would restate a verdict adopted
/// at 16 ms at 32, 64, 128 and so on — a burst of repetition in the first
/// second, which is the failure this suppression exists to prevent.
fn nextMilestone(previous_dwell_ms: u64, settle_ms: u64) u64 {
    if (previous_dwell_ms < settle_ms) return settle_ms;
    return previous_dwell_ms *| 2;
}

test "a frontier that is moving reports progress and nothing else" {
    var monitor = Monitor{};
    _ = monitor.observe(.{ .now_ms = 0, .frontier = .initialize_engines, .precondition_met = true });
    const report = monitor.observe(.{
        .now_ms = 100,
        .frontier = .ring_buffer,
        .precondition_met = true,
        .guest_originated_events = 5,
    });
    try std.testing.expect(report != null);
    try std.testing.expectEqual(Verdict.advancing, report.?.verdict);
    try std.testing.expectEqual(@as(?u16, null), report.?.notificationCode());
}

// The suppression is the point: a watchdog sampled every vblank must not
// restate the same verdict every vblank, or the one line that matters is buried
// under thousands that do not.
test "an unchanged verdict is reported once, not once per sample" {
    var monitor = Monitor{};
    var now: u64 = 0;
    _ = monitor.observe(.{ .now_ms = now, .frontier = .ring_write_pointer, .precondition_met = true });

    var emitted: usize = 0;
    // Sixteen seconds of 60 Hz sampling with nothing changing at all.
    while (now < 16_000) : (now += 16) {
        const report = monitor.observe(.{
            .now_ms = now,
            .frontier = .ring_write_pointer,
            .precondition_met = true,
            .guest_originated_events = 5,
            .host_originated_events = 5,
        });
        if (report != null) emitted += 1;
    }
    try std.testing.expect(emitted <= 8);
    try std.testing.expect(monitor.suppressed_samples > 900);
}

// The verdict a frontier report cannot reach: the host is fine, the guest
// stopped. Everything downstream of this — the zero write pointer, the zero
// swap count, the zero refresh attempts — is a consequence, not a lead.
test "host events rising while guest events are frozen means the guest stopped" {
    var monitor = Monitor{};
    _ = monitor.observe(.{
        .now_ms = 0,
        .frontier = .ring_write_pointer,
        .precondition_met = true,
        .guest_originated_events = 42,
        .host_originated_events = 0,
    });

    var now: u64 = 0;
    var host: u64 = 0;
    var last: ?Report = null;
    while (now < 6_000) : (now += 16) {
        host += 1;
        if (monitor.observe(.{
            .now_ms = now,
            .frontier = .ring_write_pointer,
            .precondition_met = true,
            .guest_originated_events = 42, // frozen
            .host_originated_events = host, // still ticking
        })) |report| last = report;
    }
    try std.testing.expect(last != null);
    try std.testing.expectEqual(Verdict.producer_dead, last.?.verdict);
    try std.testing.expect(last.?.notificationCode() != null);
    try std.testing.expect(std.mem.indexOf(u8, last.?.verdict.describe(), "has stopped") != null);
}

// A guest that is still doing other work has not stopped, however long this
// particular step takes. Calling that dead would send the reader after a fault
// that never happened.
test "a guest still producing events elsewhere is awaited, not declared dead" {
    var monitor = Monitor{};
    var now: u64 = 0;
    var events: u64 = 0;
    var host: u64 = 0;
    var last: ?Report = null;
    while (now < 6_000) : (now += 16) {
        events += 1;
        host += 1;
        if (monitor.observe(.{
            .now_ms = now,
            .frontier = .ring_write_pointer,
            .precondition_met = true,
            .guest_originated_events = events,
            .host_originated_events = host,
            .refresh_attempts = 1,
            .refresh_successes = 1,
        })) |report| last = report;
    }
    try std.testing.expect(last != null);
    try std.testing.expectEqual(Verdict.awaiting_guest, last.?.verdict);
}

// When both sides are idle there is no starvation to detect, and a verdict
// resting on the asymmetry must not fire without it.
test "silence on both sides is not a dead producer" {
    var monitor = Monitor{};
    var now: u64 = 0;
    var last: ?Report = null;
    while (now < 8_000) : (now += 16) {
        if (monitor.observe(.{
            .now_ms = now,
            .frontier = .graphics_interrupt_callback,
            .precondition_met = true,
            .guest_originated_events = 3,
            .host_originated_events = 3,
        })) |report| last = report;
    }
    try std.testing.expect(last != null);
    try std.testing.expect(last.?.verdict != .producer_dead);
}

// A stalled step whose precondition is unmet is a symptom. Saying so is what
// stops the next hour being spent on it.
test "an unreachable step is named a symptom rather than a stall" {
    var monitor = Monitor{};
    _ = monitor.observe(.{ .now_ms = 0, .frontier = .ring_write_pointer, .precondition_met = false });
    const report = monitor.observe(.{
        .now_ms = 2_000,
        .frontier = .ring_write_pointer,
        .precondition_met = false,
        .guest_originated_events = 1,
    });
    try std.testing.expect(report != null);
    try std.testing.expectEqual(Verdict.stalled_upstream, report.?.verdict);
    try std.testing.expect(std.mem.indexOf(u8, report.?.verdict.describe(), "upstream") != null);
}

// Consumer-side faults belong to the consumer, and separating "never attempted"
// from "attempted and failed" is what decides whether to read the refresh path
// at all.
test "a ready pipeline that never attempts refresh names the consumer" {
    var monitor = Monitor{};
    _ = monitor.observe(.{ .now_ms = 0, .frontier = .swap, .precondition_met = true });
    const report = monitor.observe(.{
        .now_ms = 2_000,
        .frontier = .swap,
        .precondition_met = true,
        .guest_originated_events = 1,
        .refresh_attempts = 0,
    });
    try std.testing.expect(report != null);
    try std.testing.expectEqual(Verdict.refresh_never_attempted, report.?.verdict);
}

test "refresh attempted and never succeeding is a fault inside the attempt path" {
    var monitor = Monitor{};
    _ = monitor.observe(.{ .now_ms = 0, .frontier = .swap, .precondition_met = true });
    const report = monitor.observe(.{
        .now_ms = 2_000,
        .frontier = .swap,
        .precondition_met = true,
        .guest_originated_events = 1,
        .refresh_attempts = 90,
        .refresh_successes = 0,
    });
    try std.testing.expect(report != null);
    try std.testing.expectEqual(Verdict.refresh_always_failing, report.?.verdict);
}

// Early bootstrap steps must not be blamed on the refresh path: no refresh was
// owed yet, so reporting one missing would be inventing a second fault.
test "refresh is not blamed before the guest has submitted anything" {
    var monitor = Monitor{};
    _ = monitor.observe(.{ .now_ms = 0, .frontier = .ring_buffer, .precondition_met = true });
    const report = monitor.observe(.{
        .now_ms = 2_000,
        .frontier = .ring_buffer,
        .precondition_met = true,
        .guest_originated_events = 1,
        .refresh_attempts = 0,
    });
    try std.testing.expect(report != null);
    try std.testing.expectEqual(Verdict.awaiting_guest, report.?.verdict);
}

// A change of verdict is always news, even mid-dwell, or the transition from
// "waiting" to "the guest died" would wait for a milestone to be announced.
test "a verdict change is emitted immediately rather than at the next milestone" {
    var monitor = Monitor{};
    _ = monitor.observe(.{ .now_ms = 0, .frontier = .ring_write_pointer, .precondition_met = true, .guest_originated_events = 1 });
    const waiting = monitor.observe(.{
        .now_ms = 1_500,
        .frontier = .ring_write_pointer,
        .precondition_met = true,
        .guest_originated_events = 1,
        .host_originated_events = 1,
    });
    try std.testing.expect(waiting != null);
    try std.testing.expectEqual(Verdict.awaiting_guest, waiting.?.verdict);

    const died = monitor.observe(.{
        .now_ms = 3_100,
        .frontier = .ring_write_pointer,
        .precondition_met = true,
        .guest_originated_events = 1,
        .host_originated_events = 1_000,
    });
    try std.testing.expect(died != null);
    try std.testing.expectEqual(Verdict.producer_dead, died.?.verdict);
}

test "milestones widen rather than repeating, and never inside the settle time" {
    try std.testing.expectEqual(default_settle_ms, nextMilestone(0, default_settle_ms));
    try std.testing.expectEqual(default_settle_ms, nextMilestone(16, default_settle_ms));
    try std.testing.expectEqual(@as(u64, 2_000), nextMilestone(1_000, default_settle_ms));
    try std.testing.expectEqual(@as(u64, 8_000), nextMilestone(4_000, default_settle_ms));
}
