//! Releasing a wait nobody will ever satisfy, and — the actual point — finding
//! out which bug you have from what happens next.
//!
//! A thread parked on an object nothing has ever signalled admits exactly two
//! explanations, and they live in different codebases:
//!
//!   * **A lost wakeup.** Someone did signal, and the runtime's own primitive
//!     dropped it. The predicate is satisfied and the waiter is asleep for no
//!     reason. This is the host's defect.
//!   * **An unsatisfied predicate.** Nobody signalled because the code that
//!     would have has not run. The waiter is correct to be asleep. This is the
//!     guest's defect, and no amount of host work fixes it.
//!
//! Nothing distinguishes them from the outside. Both show a parked thread, a
//! zero-notification object, and a run going nowhere — which is why "find who
//! should signal it and confirm they ran" has been the standing advice and why
//! it has not been actionable.
//!
//! One bounded spurious wake separates them completely. A POSIX condition
//! variable is permitted to wake spuriously, so every correct waiter re-checks
//! its predicate on return. Grant one wake and watch:
//!
//!   * The waiter proceeds and the run advances → the predicate *was* satisfied
//!     → lost wakeup.
//!   * The waiter re-parks immediately → the predicate is *provably*
//!     unsatisfied → the producer never ran.
//!
//! Either outcome is decisive, which is what makes this a diagnostic rather
//! than a workaround. It is a workaround only if you stop reading after the
//! run keeps going.
//!
//! ## Why it is strictly bounded
//!
//! An unbounded release turns a deadlock into a livelock and a diagnostic into
//! a lie: the run "keeps working" because something keeps kicking it, and the
//! defect is now invisible. So each object gets a small fixed number of
//! attempts, the run gets a total budget, and both are reported — a release
//! budget that ran out is itself a finding.

const std = @import("std");

/// Attempts per object. One proves the point; a second covers a wake that
/// raced with the waiter re-parking. A third would be someone hoping.
pub const max_attempts_per_object: u32 = 2;

/// Attempts across the whole run. Small on purpose: this is an experiment, and
/// an experiment that runs hundreds of times is a policy.
pub const max_attempts_total: u32 = 16;

/// Steps after a release within which progress counts as caused by it. Beyond
/// this the run advanced for its own reasons and claiming credit would turn a
/// diagnostic into a story.
pub const attribution_window_steps: u64 = 50_000_000;

/// Why a release was or was not authorised. Each refusal names a different
/// missing precondition, because "not authorised" alone sends a reader nowhere.
pub const Authorisation = enum(u8) {
    authorised,
    /// The object has been signalled at some point, so it is not the never-
    /// notified case and a wake would prove nothing.
    refused_object_has_notifier,
    /// Nothing is parked on it.
    refused_no_waiter,
    /// The waiter has not been parked long enough for its silence to mean
    /// anything.
    refused_window_too_short,
    /// This object has had its attempts.
    refused_object_budget,
    /// The run has had its attempts.
    refused_run_budget,

    pub fn label(self: Authorisation) []const u8 {
        return switch (self) {
            .authorised => "authorised",
            .refused_object_has_notifier => "refused_object_has_notifier",
            .refused_no_waiter => "refused_no_waiter",
            .refused_window_too_short => "refused_window_too_short",
            .refused_object_budget => "refused_object_budget",
            .refused_run_budget => "refused_run_budget",
        };
    }

    pub fn granted(self: Authorisation) bool {
        return self == .authorised;
    }

    pub fn meaning(self: Authorisation) []const u8 {
        return switch (self) {
            .authorised => "one bounded spurious wake is authorised. A correct waiter re-checks its predicate on return, so whichever way this goes it is decisive: progress means the signal was lost, and an immediate re-park means the predicate is genuinely unsatisfied",
            .refused_object_has_notifier => "something has signalled this object, so it is not the never-notified case and a wake would prove nothing about it",
            .refused_no_waiter => "nothing is parked on this object, so there is nobody to release",
            .refused_window_too_short => "the waiter has not been parked long enough for its silence to be evidence of anything",
            .refused_object_budget => "this object has already had its attempts. Repeating them would turn a deadlock into a livelock and hide the defect behind something that keeps kicking it",
            .refused_run_budget => "the run's total release budget is spent. That budget being exhausted is itself a finding: this many distinct objects should not need releasing",
        };
    }
};

/// What a release proved.
pub const Outcome = enum(u8) {
    /// Granted; not enough time has passed to judge.
    pending,
    /// The run advanced within the attribution window. The signal existed and
    /// the runtime dropped it.
    lost_wakeup,
    /// The waiter re-parked on the same object. The predicate is genuinely
    /// unsatisfied.
    predicate_unsatisfied,
    /// Neither: the waiter did not re-park and nothing advanced.
    inconclusive,

    pub fn label(self: Outcome) []const u8 {
        return switch (self) {
            .pending => "pending",
            .lost_wakeup => "LOST_WAKEUP",
            .predicate_unsatisfied => "PREDICATE_UNSATISFIED",
            .inconclusive => "inconclusive",
        };
    }

    pub fn meaning(self: Outcome) []const u8 {
        return switch (self) {
            .pending => "the wake was granted and the attribution window has not closed yet",
            .lost_wakeup => "the run advanced after a single spurious wake, so the waiter's predicate was already satisfied and it was asleep for no reason. The signal existed and this runtime's own primitive dropped it — the defect is here, not in the guest",
            .predicate_unsatisfied => "the waiter re-parked on the same object immediately. A correct waiter re-checks its predicate on return, so the predicate is provably unsatisfied: the code that should have published the state it waits on never ran. The defect is in the guest, and no host-side wake will ever fix it",
            .inconclusive => "the waiter neither re-parked nor produced progress within the window. Either it took a path that leads somewhere else, or the run is slow enough that the window closed too early",
        };
    }

    /// Whether this outcome settles the question.
    pub fn decisive(self: Outcome) bool {
        return self == .lost_wakeup or self == .predicate_unsatisfied;
    }
};

pub const max_objects = 12;

pub const Attempt = struct {
    object: u64 = 0,
    handle: u32 = 0,
    thread: u64 = 0,
    attempts: u32 = 0,
    released_step: u64 = 0,
    outcome: Outcome = .pending,
    /// Progress witness at the moment of release, so the outcome is judged
    /// against a number rather than an impression.
    progress_before: u64 = 0,
    progress_after: u64 = 0,
    /// Whether the runtime has fetched and reported the waited-on state for
    /// this attempt. Set once per attempt — a predicate that provably never
    /// gets satisfied is the same finding re-reported every heartbeat, and
    /// repeating the fetch would bury the first one under its own copies.
    state_fetched: bool = false,
};

pub const Ledger = struct {
    attempts: [max_objects]Attempt = [_]Attempt{.{}} ** max_objects,
    count: usize = 0,
    total_attempts: u32 = 0,
    refusals: u64 = 0,
    last_refusal: ?Authorisation = null,

    fn find(self: *Ledger, object: u64) ?*Attempt {
        for (self.attempts[0..self.count]) |*attempt| {
            if (attempt.object == object) return attempt;
        }
        return null;
    }

    /// Whether a release may be granted, and why not when it may not.
    pub fn authorise(
        self: *Ledger,
        object: u64,
        waiters: u32,
        notifications: u64,
        parked_steps: u64,
        minimum_parked_steps: u64,
    ) Authorisation {
        const decision = blk: {
            if (notifications != 0) break :blk Authorisation.refused_object_has_notifier;
            if (waiters == 0) break :blk Authorisation.refused_no_waiter;
            if (parked_steps < minimum_parked_steps) break :blk Authorisation.refused_window_too_short;
            if (self.total_attempts >= max_attempts_total) break :blk Authorisation.refused_run_budget;
            if (self.find(object)) |attempt| {
                if (attempt.attempts >= max_attempts_per_object) break :blk Authorisation.refused_object_budget;
            }
            break :blk Authorisation.authorised;
        };
        if (!decision.granted()) {
            self.refusals +|= 1;
            self.last_refusal = decision;
        }
        return decision;
    }

    /// Record that a release happened. `progress` is the independent witness
    /// the outcome will be judged against.
    pub fn noteReleased(self: *Ledger, object: u64, handle: u32, thread: u64, progress: u64, step: u64) void {
        self.total_attempts +|= 1;
        if (self.find(object)) |attempt| {
            attempt.attempts +|= 1;
            attempt.released_step = step;
            attempt.progress_before = progress;
            attempt.progress_after = progress;
            attempt.outcome = .pending;
            attempt.thread = thread;
            if (handle != 0) attempt.handle = handle;
            return;
        }
        if (self.count == max_objects) return;
        self.attempts[self.count] = .{
            .object = object,
            .handle = handle,
            .thread = thread,
            .attempts = 1,
            .released_step = step,
            .progress_before = progress,
            .progress_after = progress,
        };
        self.count += 1;
    }

    /// Judge every pending release against the current state.
    ///
    /// `re_parked` is supplied by the caller because only the scheduler knows
    /// whether the same thread went back to sleep on the same object.
    pub fn settle(self: *Ledger, object: u64, progress: u64, re_parked: bool, step: u64) void {
        const attempt = self.find(object) orelse return;
        if (attempt.outcome != .pending) return;
        attempt.progress_after = progress;
        if (progress > attempt.progress_before) {
            attempt.outcome = .lost_wakeup;
            return;
        }
        if (re_parked) {
            attempt.outcome = .predicate_unsatisfied;
            return;
        }
        if (step > attempt.released_step and step - attempt.released_step >= attribution_window_steps) {
            attempt.outcome = .inconclusive;
        }
    }

    /// Mark an attempt whose waited-on state has been fetched, so the report
    /// is emitted once per attempt rather than once per heartbeat. The whole
    /// point of the fetch is to name what the waiter is actually waiting on;
    /// naming it repeatedly is how a decisive diagnostic turns into log noise.
    pub fn markStateFetched(self: *Ledger, object: u64) void {
        if (self.find(object)) |attempt| attempt.state_fetched = true;
    }

    pub fn decisiveCount(self: *const Ledger) u32 {
        var count: u32 = 0;
        for (self.attempts[0..self.count]) |attempt| {
            if (attempt.outcome.decisive()) count += 1;
        }
        return count;
    }

    /// The attempt a reader should look at: a decided one first, newest wins.
    pub fn headline(self: *const Ledger) ?Attempt {
        var chosen: ?Attempt = null;
        for (self.attempts[0..self.count]) |attempt| {
            if (!attempt.outcome.decisive()) continue;
            if (chosen == null or attempt.released_step > chosen.?.released_step) chosen = attempt;
        }
        if (chosen != null) return chosen;
        for (self.attempts[0..self.count]) |attempt| {
            if (chosen == null or attempt.released_step > chosen.?.released_step) chosen = attempt;
        }
        return chosen;
    }

    pub fn verdict(self: *const Ledger) []const u8 {
        if (self.count == 0 and self.refusals == 0)
            return "no stalled object has been considered for release yet";
        if (self.count == 0)
            return "every candidate was refused, so nothing was released. The refusal reason is the finding: it names the precondition a release would have needed";
        if (self.headline()) |attempt| return attempt.outcome.meaning();
        return "releases were granted and none has been judged yet";
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const parked_long: u64 = 1_000_000_000;
const stall_gate: u64 = 50_000_000;

test "a release is authorised only for a never-notified object with a stuck waiter" {
    var ledger = Ledger{};
    try std.testing.expectEqual(
        Authorisation.authorised,
        ledger.authorise(0x40004BF4, 2, 0, parked_long, stall_gate),
    );

    // Every refusal names a different missing precondition.
    try std.testing.expectEqual(
        Authorisation.refused_object_has_notifier,
        ledger.authorise(0x40004BF4, 2, 5, parked_long, stall_gate),
    );
    try std.testing.expectEqual(
        Authorisation.refused_no_waiter,
        ledger.authorise(0x40004BF4, 0, 0, parked_long, stall_gate),
    );
    try std.testing.expectEqual(
        Authorisation.refused_window_too_short,
        ledger.authorise(0x40004BF4, 2, 0, 100, stall_gate),
    );
    try std.testing.expectEqual(@as(u64, 3), ledger.refusals);
}

// The whole point: the outcome names which codebase the defect is in.
test "progress after a release proves the signal was lost by the host" {
    var ledger = Ledger{};
    ledger.noteReleased(0x40004BF4, 0xF8000154, 0x7fff2080, 10, 1000);
    try std.testing.expectEqual(Outcome.pending, ledger.attempts[0].outcome);

    ledger.settle(0x40004BF4, 11, false, 2000);
    try std.testing.expectEqual(Outcome.lost_wakeup, ledger.attempts[0].outcome);
    try std.testing.expect(ledger.attempts[0].outcome.decisive());
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "defect is here, not in the guest") != null);
}

test "an immediate re-park proves the predicate is genuinely unsatisfied" {
    var ledger = Ledger{};
    ledger.noteReleased(0x40004BF4, 0xF8000154, 0x7fff2080, 10, 1000);
    ledger.settle(0x40004BF4, 10, true, 1100);
    try std.testing.expectEqual(Outcome.predicate_unsatisfied, ledger.attempts[0].outcome);
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "never ran") != null);
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "no host-side wake will ever fix it") != null);
}

// An unbounded release turns a deadlock into a livelock and the diagnostic into
// a lie: the run keeps going because something keeps kicking it.
test "an object gets a small fixed number of attempts and no more" {
    var ledger = Ledger{};
    var index: u32 = 0;
    while (index < max_attempts_per_object) : (index += 1) {
        try std.testing.expectEqual(
            Authorisation.authorised,
            ledger.authorise(0x40004BF4, 2, 0, parked_long, stall_gate),
        );
        ledger.noteReleased(0x40004BF4, 0xF8000154, 0x7fff2080, 10, 1000 + index);
    }
    try std.testing.expectEqual(
        Authorisation.refused_object_budget,
        ledger.authorise(0x40004BF4, 2, 0, parked_long, stall_gate),
    );
    try std.testing.expect(std.mem.indexOf(u8, Authorisation.refused_object_budget.meaning(), "livelock") != null);
}

test "the run has a total budget and its exhaustion is itself a finding" {
    var ledger = Ledger{};
    const object: u64 = 0x4000_0000;
    var granted: u32 = 0;
    while (granted < max_attempts_total) : (granted += 1) {
        const decision = ledger.authorise(object + granted * 0x10, 1, 0, parked_long, stall_gate);
        try std.testing.expectEqual(Authorisation.authorised, decision);
        ledger.noteReleased(object + granted * 0x10, 0, 1, 0, granted);
    }
    try std.testing.expectEqual(
        Authorisation.refused_run_budget,
        ledger.authorise(0x9000_0000, 1, 0, parked_long, stall_gate),
    );
    try std.testing.expect(std.mem.indexOf(u8, Authorisation.refused_run_budget.meaning(), "itself a finding") != null);
}

// Claiming credit for progress that happened for its own reasons turns a
// diagnostic into a story.
test "progress long after a release is not attributed to it" {
    var ledger = Ledger{};
    ledger.noteReleased(0x40004BF4, 0xF8000154, 0x7fff2080, 10, 1000);
    ledger.settle(0x40004BF4, 10, false, 1000 + attribution_window_steps + 1);
    try std.testing.expectEqual(Outcome.inconclusive, ledger.attempts[0].outcome);
    try std.testing.expect(!ledger.attempts[0].outcome.decisive());
}

test "a settled attempt is not re-judged by later events" {
    var ledger = Ledger{};
    ledger.noteReleased(0x40004BF4, 0xF8000154, 0x7fff2080, 10, 1000);
    ledger.settle(0x40004BF4, 10, true, 1100);
    try std.testing.expectEqual(Outcome.predicate_unsatisfied, ledger.attempts[0].outcome);
    ledger.settle(0x40004BF4, 99, false, 1200);
    try std.testing.expectEqual(Outcome.predicate_unsatisfied, ledger.attempts[0].outcome);
}

// A decisive predicate fetch is reported once per attempt. Repeating it every
// heartbeat would bury the finding under its own copies.
test "the state fetch is marked once per attempt" {
    var ledger = Ledger{};
    ledger.noteReleased(0x40004BF4, 0xF8000154, 0x7fff2080, 10, 1000);
    try std.testing.expect(!ledger.attempts[0].state_fetched);

    ledger.settle(0x40004BF4, 10, true, 1100);
    try std.testing.expectEqual(Outcome.predicate_unsatisfied, ledger.attempts[0].outcome);
    try std.testing.expectEqual(@as(u32, 1), ledger.decisiveCount());

    ledger.markStateFetched(0x40004BF4);
    try std.testing.expect(ledger.attempts[0].state_fetched);
    // Marking an attempt that is not in the ledger changes nothing.
    ledger.markStateFetched(0x9999);
    try std.testing.expectEqual(@as(u32, 1), ledger.decisiveCount());
}

test "a decided attempt outranks a pending one in what to read first" {
    var ledger = Ledger{};
    ledger.noteReleased(0x1000, 0, 1, 0, 100);
    ledger.noteReleased(0x2000, 0, 2, 0, 200);
    // Newest pending wins while nothing is decided.
    try std.testing.expectEqual(@as(u64, 0x2000), ledger.headline().?.object);

    ledger.settle(0x1000, 5, false, 150);
    try std.testing.expectEqual(@as(u64, 0x1000), ledger.headline().?.object);
    try std.testing.expectEqual(@as(u32, 1), ledger.decisiveCount());
}

test "a run where everything was refused says so rather than reporting silence" {
    var ledger = Ledger{};
    _ = ledger.authorise(0x1000, 0, 0, parked_long, stall_gate);
    try std.testing.expectEqual(@as(usize, 0), ledger.count);
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "refusal reason is the finding") != null);
}

test "every authorisation and outcome explains itself" {
    inline for (.{
        Authorisation.authorised, Authorisation.refused_object_has_notifier,
        Authorisation.refused_no_waiter, Authorisation.refused_window_too_short,
        Authorisation.refused_object_budget, Authorisation.refused_run_budget,
    }) |authorisation| {
        try std.testing.expect(authorisation.label().len > 0);
        try std.testing.expect(authorisation.meaning().len > 40);
    }
    inline for (.{ Outcome.pending, Outcome.lost_wakeup, Outcome.predicate_unsatisfied, Outcome.inconclusive }) |outcome| {
        try std.testing.expect(outcome.label().len > 0);
        try std.testing.expect(outcome.meaning().len > 40);
    }
    const empty = Ledger{};
    try std.testing.expect(std.mem.indexOf(u8, empty.verdict(), "no stalled object") != null);
}
