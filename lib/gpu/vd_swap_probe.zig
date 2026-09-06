//! What each VdSwap-contract probe achieved, as distinct from what it found.
//!
//! The contract ledger next door records facts.  This file records *attempts*,
//! and the difference is the whole point.  A stage that reads `state=NO
//! count=0` can mean three unrelated things:
//!
//!   1. no code path ever tried to observe it;
//!   2. a code path tried and its input was empty or unreadable;
//!   3. a code path read real data and the fact was genuinely absent.
//!
//! Only (3) is evidence about the title or the emulator.  (1) and (2) are
//! evidence about Rosette, and reporting them as if they were (3) sends a
//! reader to the guest producer to explain a hole in the observer.  That is not
//! a hypothetical: the run this file was written against reported nineteen
//! unmet stages, and six of them were unmet because the stateful command
//! processor was gated behind an outstanding span that a drained ring can never
//! produce.  The register file was never written, so every register-derived
//! stage read zero, and every one of those zeroes was printed in the same shape
//! as the genuine finding sitting next to it.
//!
//! The ledger is fixed-size and O(1) per record: it lives on the hot Mach-O
//! state object and is written from ring-scan checkpoints.

const std = @import("std");
const contract = @import("xenia_vd_swap_contract");

pub const Stage = contract.Stage;
pub const Probe = contract.Probe;
pub const ProbeOutcome = contract.ProbeOutcome;
pub const Attribution = contract.Attribution;
pub const Chain = contract.Chain;
pub const StarvationCause = contract.StarvationCause;
pub const StarvationOwner = contract.StarvationOwner;

pub const stage_count = contract.stage_count;
pub const probe_count = contract.probe_count;

/// One (stage, probe) cell.  `outcome` is the strongest result this probe has
/// ever produced for this stage, not the most recent one: a probe that
/// observed the fact once and was starved on every later heartbeat has still
/// observed it, and a probe that read real data once has still read real data.
/// Keeping the strongest result stops a quiet tail of empty checkpoints from
/// erasing a finding that was made early.
pub const Cell = struct {
    outcome: ProbeOutcome = .not_attempted,
    /// The most recent outcome, retained separately so a probe that used to
    /// work and has since gone blind is still legible.
    latest: ProbeOutcome = .not_attempted,
    attempts: u64 = 0,
    evidence_attempts: u64 = 0,
    starved_attempts: u64 = 0,
    /// What the most recent starvation was missing. Retained rather than
    /// summarised because a probe that used to starve on unreadable memory and
    /// now starves on a drained input has changed, and a count cannot say so.
    starvation_cause: StarvationCause = .unspecified,
    /// Starvations recorded with no cause. A non-zero count is a wiring gap at
    /// a call site, and keeping it visible is what stops `unspecified` from
    /// quietly becoming the common answer.
    unattributed_starvations: u64 = 0,
    /// The step of the first starvation, so a probe that has been blind since
    /// the beginning is distinguishable from one that went blind.
    first_starved_step: u64 = 0,
    /// A probe-defined magnitude: dwords examined, packets walked, registers
    /// read.  Zero alongside a `negative` outcome is a contradiction worth
    /// seeing, which is why it is retained rather than summarised.
    detail: u64 = 0,
    first_step: u64 = 0,
    last_step: u64 = 0,

    pub fn attempted(self: Cell) bool {
        return self.attempts != 0;
    }
};

/// How strong an outcome is when deciding what a probe has achieved overall.
/// `observed` beats `negative` beats a refusal beats any starvation, and an
/// attempt of any kind beats never having run.
fn rank(outcome: ProbeOutcome) u8 {
    return switch (outcome) {
        .not_attempted => 0,
        .input_unavailable => 1,
        .input_empty => 2,
        .refused_by_owner => 3,
        .negative => 4,
        .observed => 5,
    };
}

pub const StageDiagnosis = struct {
    stage: Stage,
    chain: Chain,
    attribution: Attribution,
    /// The unmet prerequisite that makes this stage `blocked_upstream`, if any.
    blocked_by: ?Stage = null,
    /// The probe whose outcome decided the attribution.
    decided_by: ?Probe = null,
    decided_outcome: ProbeOutcome = .not_attempted,
    probes_total: usize = 0,
    probes_attempted: usize = 0,
    probes_with_evidence: usize = 0,
    probes_starved: usize = 0,
    /// The cause behind the starvation of the probe that decided this stage,
    /// or of the first starved probe when the deciding one was not starved.
    starvation_cause: StarvationCause = .unspecified,
    detail: u64 = 0,
    last_step: u64 = 0,

    pub fn met(self: StageDiagnosis) bool {
        return self.attribution == .met;
    }

    /// True when this stage is a real wall: its prerequisites hold, so work
    /// aimed at it is not wasted on something downstream.
    pub fn actionable(self: StageDiagnosis) bool {
        return switch (self.attribution) {
            .actionable, .starved, .unprobed => true,
            .met, .blocked_upstream => false,
        };
    }

    /// True when the reason this stage is unmet is a defect in Rosette's
    /// observation rather than a fact about the title or the emulator.
    pub fn observerDefect(self: StageDiagnosis) bool {
        return self.attribution == .starved or self.attribution == .unprobed;
    }
};

pub const Summary = struct {
    met: usize = 0,
    blocked_upstream: usize = 0,
    unprobed: usize = 0,
    starved: usize = 0,
    actionable: usize = 0,
    /// Starved stages Rosette can un-starve on its own — an unwired probe or a
    /// counter nothing feeds. Separated from the total because the rest are
    /// waiting on a fact that has not happened, and no observer work brings
    /// that forward.
    starved_closable_by_rosette: usize = 0,
    /// Starved stages whose cause was never recorded. A wiring gap at a call
    /// site, and the first thing to close: until it is zero the report can say
    /// a stage was unobserved and cannot say what it was missing.
    starved_unattributed: usize = 0,
    /// Actionable stages whose deciding probe declined by owner rule rather
    /// than reading anything.
    ///
    /// These are genuine findings — a policy refused an observation that was
    /// possible — and they are not the same finding as "a probe read real data
    /// and the fact was absent". Counting them together made `findings=6` mean
    /// two different things at once, and only one of them is answered by
    /// looking at the stage's owner.
    refused_by_owner: usize = 0,

    pub fn unmet(self: Summary) usize {
        return self.blocked_upstream + self.unprobed + self.starved + self.actionable;
    }

    /// Stages whose zero is Rosette's fault.  Non-zero here means the contract
    /// is reporting its own blind spots as findings, and no conclusion about
    /// the title should be drawn until it reaches zero.
    pub fn observerDefects(self: Summary) usize {
        return self.unprobed + self.starved;
    }

    pub fn verdict(self: Summary) []const u8 {
        if (self.unmet() == 0) return "every stage is observed; the handoff is complete";
        if (self.unprobed != 0) {
            return "at least one stage with satisfied prerequisites has never been probed: the contract is reporting a hole in the observer as an absence in the title. Wire the probe before reading any zero below it";
        }
        if (self.starved_unattributed != 0) {
            return "at least one stage was probed only with empty or unreadable input and nothing recorded what was missing. Record the cause at the probe's call site: an unobserved stage with no named cause names no work";
        }
        if (self.starved_closable_by_rosette != 0) {
            return "at least one stage is unobserved because its probe is not wired or reads a counter nothing feeds. That is Rosette's to close today and it needs nothing from the guest or the emulator";
        }
        if (self.starved != 0) {
            return "at least one stage was probed only with empty or unreadable input: it has not been shown false, only unobserved. The recorded causes name what has not been produced yet, so the work is upstream of the probe rather than in it";
        }
        if (self.refused_by_owner != 0 and self.refused_by_owner == self.actionable) {
            return "every unmet stage with satisfied prerequisites was decided by a probe that declined under an owner rule rather than by one that read data. The observation was possible and policy refused it: change the policy or the owner, and do not read these as absences in the title";
        }
        if (self.refused_by_owner != 0) {
            return "the unmet stages with satisfied prerequisites are a mix: some were read against real data and are findings against their owners, and some were refused by an owner rule and are findings against the rule. The two are answered in different places";
        }
        return "every unmet stage with satisfied prerequisites was probed against real data; the remaining gaps are findings against their stage owners";
    }
};

pub const Ledger = struct {
    cells: [stage_count][probe_count]Cell = .{.{Cell{}} ** probe_count} ** stage_count,
    records: u64 = 0,
    /// Records that named a probe not listed for the stage.  A non-zero count
    /// means the static `probesFor` table and the runtime wiring disagree, and
    /// the diagnosis below it is incomplete rather than wrong.
    unlisted_probe_records: u64 = 0,
    /// Starvations recorded with no cause, across every cell.  Non-zero means
    /// the report can say a stage was unobserved and cannot say what it was
    /// missing, which is a gap in Rosette's own call sites.
    unattributed_starvations: u64 = 0,

    pub fn cell(self: *const Ledger, stage: Stage, probe: Probe) Cell {
        return self.cells[@intFromEnum(stage)][@intFromEnum(probe)];
    }

    /// Record one run of one probe against one stage.  Deliberately cheap and
    /// unconditional: the negative and starved outcomes are the ones worth
    /// having, so a caller must never skip the call because it found nothing.
    pub fn record(
        self: *Ledger,
        stage: Stage,
        probe: Probe,
        outcome: ProbeOutcome,
        detail: u64,
        step: u64,
    ) void {
        self.recordWithCause(stage, probe, outcome, .unspecified, detail, step);
    }

    /// Record one run of one probe, together with what it was missing when it
    /// produced nothing.
    ///
    /// A starvation with no cause is the least actionable line the report can
    /// carry: it says a stage has not been shown false and gives no way to
    /// find out what would show it. Every site that knows why its input was
    /// absent says so here, and the ones that do not are counted rather than
    /// defaulted, so the gap stays visible.
    pub fn recordWithCause(
        self: *Ledger,
        stage: Stage,
        probe: Probe,
        outcome: ProbeOutcome,
        cause: StarvationCause,
        detail: u64,
        step: u64,
    ) void {
        self.records +|= 1;
        if (!probeIsListed(stage, probe)) self.unlisted_probe_records +|= 1;
        const entry = &self.cells[@intFromEnum(stage)][@intFromEnum(probe)];
        if (entry.attempts == 0) entry.first_step = step;
        entry.attempts +|= 1;
        entry.last_step = step;
        entry.latest = outcome;
        if (outcome.isEvidence()) entry.evidence_attempts +|= 1;
        if (outcome.isStarved()) {
            if (entry.starved_attempts == 0) entry.first_starved_step = step;
            entry.starved_attempts +|= 1;
            entry.starvation_cause = cause;
            if (cause == .unspecified) {
                entry.unattributed_starvations +|= 1;
                self.unattributed_starvations +|= 1;
            }
        }
        if (rank(outcome) >= rank(entry.outcome)) {
            entry.outcome = outcome;
            if (detail != 0 or outcome.isEvidence()) entry.detail = detail;
        }
    }

    /// Record the same outcome for every probe that supplies a stage.  Used by
    /// callers that own all of a stage's evidence paths at once.
    pub fn recordAll(
        self: *Ledger,
        stage: Stage,
        outcome: ProbeOutcome,
        detail: u64,
        step: u64,
    ) void {
        for (contract.probesFor(stage)) |probe| self.record(stage, probe, outcome, detail, step);
    }

    /// Record `observed` when `seen`, `negative` otherwise.  This is the shape
    /// almost every probe wants: it ran, it had input, and the answer is one of
    /// the two things a reader can act on.  A probe whose input was empty must
    /// call `record` with `.input_empty` instead — passing `false` here would
    /// claim it looked.
    pub fn observe(
        self: *Ledger,
        stage: Stage,
        probe: Probe,
        seen: bool,
        detail: u64,
        step: u64,
    ) void {
        self.record(stage, probe, if (seen) .observed else .negative, detail, step);
    }

    pub fn diagnose(self: *const Ledger, stage: Stage, observed_mask: u32) StageDiagnosis {
        var result = StageDiagnosis{
            .stage = stage,
            .chain = contract.chainOf(stage),
            .attribution = .met,
            .probes_total = contract.probesFor(stage).len,
        };

        var strongest: ProbeOutcome = .not_attempted;
        for (contract.probesFor(stage)) |probe| {
            const entry = self.cell(stage, probe);
            if (entry.attempted()) result.probes_attempted += 1;
            if (entry.outcome.isEvidence()) result.probes_with_evidence += 1;
            if (entry.attempted() and entry.outcome.isStarved()) {
                result.probes_starved += 1;
                // The first starved probe's cause stands in until the deciding
                // probe supplies one of its own. A stage whose decider read
                // real data does not need a cause; a stage whose decider was
                // starved overwrites this below.
                if (result.starvation_cause == .unspecified) {
                    result.starvation_cause = entry.starvation_cause;
                }
            }
            if (entry.last_step > result.last_step) result.last_step = entry.last_step;
            if (rank(entry.outcome) >= rank(strongest)) {
                strongest = entry.outcome;
                result.decided_by = probe;
                result.decided_outcome = entry.outcome;
                if (entry.outcome.isStarved() and entry.starvation_cause != .unspecified) {
                    result.starvation_cause = entry.starvation_cause;
                }
                if (entry.detail != 0) result.detail = entry.detail;
            }
        }

        if (observed_mask & contract.stageBit(stage) != 0) {
            result.attribution = .met;
            return result;
        }

        for (contract.dependencies(stage)) |prerequisite| {
            if (observed_mask & contract.stageBit(prerequisite) == 0) {
                result.attribution = .blocked_upstream;
                result.blocked_by = prerequisite;
                return result;
            }
        }

        // Prerequisites hold, so this stage is a wall.  Which kind of wall
        // depends entirely on whether anything managed to look at it.
        result.attribution = switch (strongest) {
            .not_attempted => .unprobed,
            .input_unavailable, .input_empty => .starved,
            // A refusal is a decision, not a blind spot: the observation was
            // possible and policy declined it, which is a finding a reader can
            // act on by changing the policy or the owner.
            .refused_by_owner, .negative, .observed => .actionable,
        };
        return result;
    }

    pub fn summary(self: *const Ledger, observed_mask: u32) Summary {
        var totals = Summary{};
        for (contract.stage_order) |stage| {
            const diagnosis = self.diagnose(stage, observed_mask);
            switch (diagnosis.attribution) {
                .met => totals.met += 1,
                .blocked_upstream => totals.blocked_upstream += 1,
                .unprobed => totals.unprobed += 1,
                .starved => {
                    totals.starved += 1;
                    if (diagnosis.starvation_cause == .unspecified) {
                        totals.starved_unattributed += 1;
                    } else if (diagnosis.starvation_cause.closableByRosette()) {
                        totals.starved_closable_by_rosette += 1;
                    }
                },
                .actionable => {
                    totals.actionable += 1;
                    if (diagnosis.decided_outcome == .refused_by_owner) {
                        totals.refused_by_owner += 1;
                    }
                },
            }
        }
        return totals;
    }

    /// The most attempts any single probe has recorded.
    ///
    /// A floor on how many times the refresh that drives every probe has run,
    /// and the only honest evidence that "this probe never ran" is a wiring
    /// gap rather than a run that has not got there yet. A cold ledger has
    /// every reachable stage unprobed and that means nothing; a ledger where
    /// one probe has a hundred attempts and another has none has a probe that
    /// is not on the driver's path, and no later checkpoint will change that.
    ///
    /// A full scan of a fixed table, called once per report rather than per
    /// step.
    pub fn maxAttempts(self: *const Ledger) u64 {
        var most: u64 = 0;
        for (self.cells) |row| {
            for (row) |entry| {
                if (entry.attempts > most) most = entry.attempts;
            }
        }
        return most;
    }

    /// The stage a reader should look at first: the actionable wall furthest
    /// upstream, preferring an observer defect over a finding because a
    /// finding made next to a blind spot is not yet trustworthy.
    pub fn primaryWall(self: *const Ledger, observed_mask: u32) ?StageDiagnosis {
        var best: ?StageDiagnosis = null;
        for (contract.stage_order) |stage| {
            const diagnosis = self.diagnose(stage, observed_mask);
            if (!diagnosis.actionable()) continue;
            const current = best orelse {
                best = diagnosis;
                continue;
            };
            if (diagnosis.observerDefect() and !current.observerDefect()) best = diagnosis;
        }
        return best;
    }
};

fn probeIsListed(stage: Stage, probe: Probe) bool {
    for (contract.probesFor(stage)) |listed| {
        if (listed == probe) return true;
    }
    return false;
}

// A cold ledger and a ledger with an unwired probe look identical stage by
// stage. What separates them is whether the driver ran at all, and that is the
// only thing that makes "never probed" a defect rather than a schedule.
test "the attempt floor separates a cold ledger from an unwired probe" {
    var ledger = Ledger{};
    try std.testing.expectEqual(@as(u64, 0), ledger.maxAttempts());

    // One probe driven a hundred times; another stage's probes never called.
    for (0..100) |round| {
        ledger.record(.guest_vdswap_entered, .guest_log_breadcrumb, .negative, 0, round);
    }
    try std.testing.expectEqual(@as(u64, 100), ledger.maxAttempts());
    // The stage nothing looked at is still unprobed, and now that is a fact
    // about the wiring rather than about the clock.
    const cold = ledger.diagnose(.frontbuffer_validated, 0);
    try std.testing.expectEqual(Attribution.unprobed, cold.attribution);
    try std.testing.expectEqual(@as(usize, 0), cold.probes_attempted);
}

test "an empty ledger reports every unmet stage as unprobed or blocked" {
    const ledger = Ledger{};
    const totals = ledger.summary(0);
    try std.testing.expectEqual(@as(usize, 0), totals.met);
    try std.testing.expectEqual(stage_count, totals.unmet());
    try std.testing.expectEqual(@as(usize, 0), totals.actionable);
    try std.testing.expectEqual(@as(usize, 0), totals.starved);
    // The stages with no prerequisites are walls nobody has looked at; the
    // rest are honestly downstream.
    try std.testing.expectEqual(contract.observedCount(contract.actionableMask(0)), totals.unprobed);
    try std.testing.expect(totals.observerDefects() != 0);
}

test "an empty span is not evidence that the guest wrote nothing" {
    var ledger = Ledger{};
    const observed = contract.stageBit(.ring_geometry_observed) |
        contract.stageBit(.ring_projection_readable);

    // The span scan ran on every heartbeat and examined zero dwords, because
    // the ring's read and write pointers agree once the batch is drained.
    var beat: u64 = 0;
    while (beat < 16) : (beat += 1) {
        ledger.record(.pm4_stream_observed, .outstanding_span_scan, .input_empty, 0, beat);
    }
    const starved = ledger.diagnose(.pm4_stream_observed, observed);
    try std.testing.expectEqual(Attribution.starved, starved.attribution);
    try std.testing.expect(starved.observerDefect());
    try std.testing.expect(starved.actionable());
    try std.testing.expectEqual(@as(u64, 16), ledger.cell(.pm4_stream_observed, .outstanding_span_scan).starved_attempts);

    // A second probe that reads the retained batch finds real dwords.  One
    // probe with evidence is enough to make the stage a finding rather than a
    // blind spot, whatever the starved probe beside it says.
    ledger.observe(.pm4_stream_observed, .retained_batch_scan, false, 25, 17);
    const decided = ledger.diagnose(.pm4_stream_observed, observed);
    try std.testing.expectEqual(Attribution.actionable, decided.attribution);
    try std.testing.expect(!decided.observerDefect());
    try std.testing.expectEqual(Probe.retained_batch_scan, decided.decided_by.?);
    try std.testing.expectEqual(@as(u64, 25), decided.detail);
    try std.testing.expectEqual(@as(usize, 1), decided.probes_with_evidence);
}

test "a stage whose prerequisites are unmet names the prerequisite" {
    var ledger = Ledger{};
    ledger.record(.native_presented, .native_presenter_counter, .negative, 0, 1);
    const diagnosis = ledger.diagnose(.native_presented, 0);
    try std.testing.expectEqual(Attribution.blocked_upstream, diagnosis.attribution);
    try std.testing.expectEqual(Stage.output_refresh_succeeded, diagnosis.blocked_by.?);
    // Even with a probe that ran, a downstream stage is not a wall: work aimed
    // at the presenter here would be aimed at the wrong subsystem.
    try std.testing.expect(!diagnosis.actionable());
}

test "the strongest outcome survives a quiet tail of empty checkpoints" {
    var ledger = Ledger{};
    ledger.observe(.draw_consumed, .stateful_pm4_execution, true, 24, 100);
    var beat: u64 = 0;
    while (beat < 64) : (beat += 1) {
        ledger.record(.draw_consumed, .stateful_pm4_execution, .input_empty, 0, 200 + beat);
    }
    const entry = ledger.cell(.draw_consumed, .stateful_pm4_execution);
    try std.testing.expectEqual(ProbeOutcome.observed, entry.outcome);
    try std.testing.expectEqual(ProbeOutcome.input_empty, entry.latest);
    try std.testing.expectEqual(@as(u64, 24), entry.detail);
    try std.testing.expectEqual(@as(u64, 65), entry.attempts);
    try std.testing.expectEqual(@as(u64, 1), entry.evidence_attempts);
    try std.testing.expectEqual(@as(u64, 64), entry.starved_attempts);
}

test "the primary wall prefers an observer defect over a finding" {
    var ledger = Ledger{};
    const observed = contract.stageBit(.ring_write_pointer_published) |
        contract.stageBit(.ring_geometry_observed) |
        contract.stageBit(.ring_projection_readable) |
        contract.stageBit(.pm4_stream_observed) |
        contract.stageBit(.pm4_stream_validated) |
        contract.stageBit(.pm4_indirects_resolved) |
        contract.stageBit(.pm4_state_programmed) |
        contract.stageBit(.draw_submitted) |
        contract.stageBit(.draw_consumed) |
        contract.stageBit(.guest_wait_observed_after_draw);

    // Five of the six walls are real findings: a probe read real data and the
    // fact was absent.  The producer wall is the strongest of them — the
    // tracepoint watched the export and it was never entered.
    ledger.recordAll(.guest_vdswap_entered, .negative, 0, 10);
    ledger.recordAll(.frontbuffer_validated, .negative, 8192, 10);
    ledger.recordAll(.xe_swap_candidate_seen, .negative, 8192, 10);
    ledger.recordAll(.draw_completion_signaled, .negative, 24, 10);
    ledger.recordAll(.guest_producer_progressed_after_draw, .negative, 0, 10);
    // The sixth is a blind spot: the register file was never written because
    // the executor never ran on this batch, so nothing looked at the target.
    ledger.record(.render_target_state_observed, .xenos_register_file, .input_empty, 0, 10);
    ledger.record(.render_target_state_observed, .stateful_pm4_execution, .not_attempted, 0, 10);

    const producer = ledger.diagnose(.guest_vdswap_entered, observed);
    try std.testing.expectEqual(Attribution.actionable, producer.attribution);
    const target = ledger.diagnose(.render_target_state_observed, observed);
    try std.testing.expectEqual(Attribution.starved, target.attribution);

    // Six walls, one of which is Rosette's.
    const totals = ledger.summary(observed);
    try std.testing.expectEqual(@as(usize, 10), totals.met);
    try std.testing.expectEqual(@as(usize, 19), totals.unmet());
    try std.testing.expectEqual(@as(usize, 13), totals.blocked_upstream);
    try std.testing.expectEqual(@as(usize, 5), totals.actionable);
    try std.testing.expectEqual(@as(usize, 1), totals.starved);
    try std.testing.expectEqual(@as(usize, 0), totals.unprobed);
    try std.testing.expectEqual(@as(usize, 1), totals.observerDefects());

    // `firstGap` would send a reader to the producer.  The producer finding is
    // sound, but it was made beside a broken observer, so the blind spot is
    // what has to be repaired before the report can be trusted.
    try std.testing.expectEqual(Stage.guest_vdswap_entered, contract.firstGap(observed).?);
    try std.testing.expectEqual(Stage.render_target_state_observed, ledger.primaryWall(observed).?.stage);
}

test "an unlisted probe is counted rather than silently accepted" {
    var ledger = Ledger{};
    ledger.record(.native_presented, .ring_geometry_capture, .observed, 0, 1);
    try std.testing.expectEqual(@as(u64, 1), ledger.unlisted_probe_records);
    ledger.record(.native_presented, .native_presenter_counter, .observed, 0, 2);
    try std.testing.expectEqual(@as(u64, 1), ledger.unlisted_probe_records);
    try std.testing.expectEqual(@as(u64, 2), ledger.records);
}

test "a complete contract has no walls and no observer defects" {
    var ledger = Ledger{};
    var observed: u32 = 0;
    for (contract.stage_order) |stage| {
        observed |= contract.stageBit(stage);
        ledger.recordAll(stage, .observed, 1, 1);
    }
    const totals = ledger.summary(observed);
    try std.testing.expectEqual(stage_count, totals.met);
    try std.testing.expectEqual(@as(usize, 0), totals.unmet());
    try std.testing.expectEqual(@as(usize, 0), totals.observerDefects());
    try std.testing.expect(ledger.primaryWall(observed) == null);
    try std.testing.expectEqual(@as(u64, 0), ledger.unlisted_probe_records);
}

// The line the 2026-09-01 run produced was `starved=1
// decided=guest-progress-counter/input-unavailable`, and it named neither what
// the counter was missing nor whether anyone could do anything about it.
test "a starved stage carries what its probe was missing" {
    var ledger = Ledger{};
    const observed: u32 = contract.stageBit(.draw_consumed);

    ledger.recordWithCause(
        .guest_producer_progressed_after_draw,
        .guest_progress_counter,
        .input_unavailable,
        .upstream_producer_idle,
        0,
        4_200_000,
    );

    const diagnosis = ledger.diagnose(.guest_producer_progressed_after_draw, observed);
    try std.testing.expectEqual(Attribution.starved, diagnosis.attribution);
    try std.testing.expectEqual(StarvationCause.upstream_producer_idle, diagnosis.starvation_cause);
    // Nothing an observer can do brings this forward, so it must not appear in
    // the count of holes Rosette can close today.
    try std.testing.expectEqual(StarvationOwner.upstream_fact, diagnosis.starvation_cause.owner());

    const cell = ledger.cell(.guest_producer_progressed_after_draw, .guest_progress_counter);
    try std.testing.expectEqual(@as(u64, 4_200_000), cell.first_starved_step);
    try std.testing.expectEqual(@as(u64, 0), cell.unattributed_starvations);

    const totals = ledger.summary(observed);
    try std.testing.expectEqual(@as(usize, 0), totals.starved_unattributed);
    try std.testing.expectEqual(@as(usize, 0), totals.starved_closable_by_rosette);
}

// A cause nobody recorded is a wiring gap at a call site. It has to be
// countable, or `unspecified` quietly becomes the common answer and the report
// is back where it started.
test "a starvation with no cause is counted rather than defaulted" {
    var ledger = Ledger{};
    const observed: u32 = contract.stageBit(.draw_consumed);
    ledger.record(.guest_producer_progressed_after_draw, .guest_progress_counter, .input_unavailable, 0, 10);

    try std.testing.expectEqual(@as(u64, 1), ledger.unattributed_starvations);
    const diagnosis = ledger.diagnose(.guest_producer_progressed_after_draw, observed);
    try std.testing.expectEqual(StarvationCause.unspecified, diagnosis.starvation_cause);
    const totals = ledger.summary(observed);
    try std.testing.expectEqual(@as(usize, 1), totals.starved_unattributed);
}

// The two starvations that are worth separating: one the guest has to reach
// and one Rosette never wired. Both read `starved=1` and only the second is
// work available today.
test "an unwired probe is separated from an input nothing has produced" {
    var ledger = Ledger{};
    const observed: u32 = contract.stageBit(.draw_consumed);
    ledger.recordWithCause(
        .guest_producer_progressed_after_draw,
        .guest_progress_counter,
        .input_unavailable,
        .source_never_fed,
        0,
        10,
    );
    const totals = ledger.summary(observed);
    try std.testing.expectEqual(@as(usize, 1), totals.starved);
    try std.testing.expectEqual(@as(usize, 1), totals.starved_closable_by_rosette);
    try std.testing.expectEqual(@as(usize, 0), totals.starved_unattributed);
}

// The verdict ranks the three kinds of starvation, because they are three
// different pieces of work and the most fixable one has to be said first. An
// unprobed stage still outranks all of them: a probe that never ran is a
// stronger statement about the observer than one that ran and found nothing.
test "the verdict names the most closable starvation first" {
    const unattributed = Summary{ .met = 1, .starved = 2, .starved_unattributed = 1, .starved_closable_by_rosette = 1 };
    try std.testing.expect(std.mem.indexOf(u8, unattributed.verdict(), "names no work") != null);

    const closable = Summary{ .met = 1, .starved = 2, .starved_closable_by_rosette = 1 };
    try std.testing.expect(std.mem.indexOf(u8, closable.verdict(), "Rosette's to close today") != null);

    const upstream = Summary{ .met = 1, .starved = 2 };
    try std.testing.expect(std.mem.indexOf(u8, upstream.verdict(), "upstream of the probe") != null);

    // An unprobed stage outranks every kind of starvation.
    const unprobed = Summary{ .met = 1, .unprobed = 1, .starved = 1, .starved_unattributed = 1 };
    try std.testing.expect(std.mem.indexOf(u8, unprobed.verdict(), "never been probed") != null);

    try std.testing.expectEqual(@as(usize, 0), (Summary{ .met = 3 }).unmet());
    try std.testing.expect(std.mem.indexOf(u8, (Summary{ .met = 3 }).verdict(), "handoff is complete") != null);
}

// The cause is the *latest* one, so a probe that used to starve on unreadable
// memory and now starves on a drained input reads as having changed.
test "the retained cause is the most recent starvation, not the first" {
    var ledger = Ledger{};
    ledger.recordWithCause(.pm4_stream_observed, .outstanding_span_scan, .input_unavailable, .memory_unreadable, 0, 10);
    try std.testing.expectEqual(
        StarvationCause.memory_unreadable,
        ledger.cell(.pm4_stream_observed, .outstanding_span_scan).starvation_cause,
    );
    ledger.recordWithCause(.pm4_stream_observed, .outstanding_span_scan, .input_empty, .input_drained, 0, 20);
    const cell = ledger.cell(.pm4_stream_observed, .outstanding_span_scan);
    try std.testing.expectEqual(StarvationCause.input_drained, cell.starvation_cause);
    // The first starvation's step is kept, so a probe blind from the start is
    // distinguishable from one that went blind later.
    try std.testing.expectEqual(@as(u64, 10), cell.first_starved_step);
    try std.testing.expectEqual(@as(u64, 2), cell.starved_attempts);
}

// A refusal and an absence read identically in a `findings=` count and are
// answered in completely different places: one by changing a policy, the other
// by looking at what the title did.
test "a stage decided by a refusal is separated from one decided by evidence" {
    var ledger = Ledger{};
    const observed: u32 = contract.stageBit(.xe_swap_packet_decoded) |
        contract.stageBit(.authentic_xe_swap_consumed);

    ledger.record(.issue_swap_entered, .presenter_tracepoint, .refused_by_owner, 0, 10);
    const refused = ledger.diagnose(.issue_swap_entered, observed);
    // A refusal is a decision, so the stage is actionable and not starved.
    try std.testing.expectEqual(Attribution.actionable, refused.attribution);
    try std.testing.expect(!refused.observerDefect());

    const totals = ledger.summary(observed);
    try std.testing.expect(totals.actionable != 0);
    try std.testing.expectEqual(@as(usize, 1), totals.refused_by_owner);
    try std.testing.expect(std.mem.indexOf(u8, (Summary{
        .met = 1,
        .actionable = 1,
        .refused_by_owner = 1,
    }).verdict(), "policy refused it") != null);

    // A stage decided by real data alongside it makes the report a mixture,
    // and the sentence has to say so rather than pick one.
    const mixed = Summary{ .met = 1, .actionable = 2, .refused_by_owner = 1 };
    try std.testing.expect(std.mem.indexOf(u8, mixed.verdict(), "answered in different places") != null);

    // No refusals at all keeps the original sentence.
    const evidenced = Summary{ .met = 1, .actionable = 2 };
    try std.testing.expect(std.mem.indexOf(u8, evidenced.verdict(), "findings against their stage owners") != null);
}
