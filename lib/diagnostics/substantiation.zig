//! Who answered for each boundary, and whether the two sides agreed.
//!
//! The contract in `rosette_substantiation_contract` decides; this keeps the
//! evidence and the history. History matters: a boundary the application
//! answered for six hundred million steps and then stopped answering for is a
//! different finding from one it never answered, and both print as a zero.
//!
//! The defect this was written against is the reading of `NEVER ENTERED` as a
//! failure. An armed tracepoint the instruction pointer never reached is only a
//! problem if nobody can answer the question that address was going to answer.
//! Rosette observes all of these boundaries. Once a causal frontier is open,
//! an explicit zero is recorded as a bounded negative answer, so the report
//! does not confuse a known absence with a boundary that was never examined.

const std = @import("std");
const contract = @import("rosette_substantiation_contract");

pub const Boundary = contract.Boundary;
pub const Evidence = contract.Evidence;
pub const Claim = contract.Claim;
pub const Answer = contract.Answer;
pub const ValueDomain = contract.ValueDomain;
pub const Finding = contract.Finding;
pub const Reading = contract.Reading;
pub const Scope = contract.Scope;
pub const boundary_count = contract.boundary_count;
pub const schema_version = contract.schema_version;

const Side = enum { application, harness };

/// Select the strongest causal phase currently proven by the run.  This is
/// deliberately derived from observed execution/GPU evidence rather than from
/// elapsed steps: startup translation can be long, but it cannot substantiate
/// a future swap boundary merely by taking time.
pub fn scopeFor(guest_main_ready: bool, gpu_activity: bool) Scope {
    if (gpu_activity) return .gpu_activity;
    if (guest_main_ready) return .application_execution;
    return .pre_application;
}

pub const Record = struct {
    application: Answer = .{},
    harness: Answer = .{},
    prerequisites_met: bool = true,
    finding: Finding = .not_reached,
    /// The strongest finding this boundary has ever reached, so a boundary that
    /// was corroborated and later fell silent is not reported as one that was
    /// never answered.
    best_finding: Finding = .not_reached,
    observations: u64 = 0,
    divergences: u64 = 0,
    first_answer_step: u64 = 0,
    last_change_step: u64 = 0,
    /// A bounded negative is an observation through a finite frontier, not a
    /// claim that the event can never happen.  If the other side later
    /// supplies a timestamped positive observation, the old negative is
    /// removed from the *current* comparison, but this count keeps the stale
    /// answer visible to diagnostics instead of silently erasing history.
    superseded_negative_answers: u64 = 0,

    pub fn answered(self: Record) bool {
        return self.application.substantiates() or self.harness.substantiates();
    }

    /// True when the boundary is settled and needs no detail in a collapsed
    /// report: somebody answered and nothing disagreed.
    pub fn settled(self: Record) bool {
        return self.finding.acceptable() and self.finding != .not_reached;
    }
};

pub const Summary = struct {
    scope: Scope = .pre_application,
    scope_armed: bool = false,
    scope_elapsed_steps: u64 = 0,
    answered: usize = 0,
    by_application: usize = 0,
    by_harness: usize = 0,
    corroborated: usize = 0,
    bounded_negative: usize = 0,
    /// Bounded negatives that were superseded by a later positive observation
    /// from the other side.  These are historical audit facts, not current
    /// answers and therefore do not make a clean summary dirty.
    superseded_negative: usize = 0,
    diverged: usize = 0,
    unsubstantiated: usize = 0,
    /// Unanswered boundaries Rosette was allowed to observe and did not. A
    /// negative observation is enough to close an event boundary; it does not
    /// grant Rosette authority to originate the event.
    unsubstantiated_answerable: usize = 0,
    not_reached: usize = 0,
    /// Numeric answers that cannot be compared because the two sides
    /// reported different semantic units. This remains a strict failure, but
    /// is kept distinct from a same-domain value disagreement.
    measurement_drifts: usize = 0,
    problem: ?Boundary = null,

    pub fn clean(self: Summary) bool {
        return self.diverged == 0 and self.measurement_drifts == 0 and self.unsubstantiated == 0;
    }

    pub fn verdict(self: Summary) []const u8 {
        if (self.measurement_drifts != 0)
            return "two sides answered a boundary with different measurement domains; the values are not comparable and Rosette refuses to choose an account until the producers report the same unit";
        if (self.diverged != 0)
            return "two sides answered one boundary differently; every conclusion drawn downstream depends on which account was read, and neither is marked as the one to trust";
        if (self.unsubstantiated_answerable != 0)
            return "a boundary Rosette is allowed to observe has no account from either side; the host observation frontier was open but no positive or explicit negative answer was published";
        if (self.unsubstantiated != 0)
            return "a boundary has no account from either side; Rosette must publish a bounded negative observation or the application must substantiate the event";
        if (self.answered == 0)
            return "no boundary has been answered yet; the run has not arrived at any of them and this report says nothing";
        if (self.by_application == 0)
            return "Rosette is answering for every boundary the application has reached. During bring-up this is the intended shape: it is what hosting means before the application is stable";
        return "every boundary the run has reached has an account, and the two sides agree wherever both gave one";
    }
};

pub const Ledger = struct {
    records: [boundary_count]Record = [_]Record{.{}} ** boundary_count,
    evaluations: u64 = 0,
    divergences: u64 = 0,
    /// The first proven guest/GPU phase arms accountability.  A later GPU
    /// phase may refine the label, but does not restart the grace clock.
    scope: Scope = .pre_application,
    scope_start_step: u64 = 0,
    scope_armed: bool = false,

    pub fn record(self: *const Ledger, boundary: Boundary) Record {
        return self.records[@intFromEnum(boundary)];
    }

    /// State one side's positive answer. Never weakens an answer already given:
    /// a side that executed a boundary once has substantiated it forever, and a
    /// later checkpoint that merely did not re-observe it is not a retraction.
    pub fn answer(
        self: *Ledger,
        boundary: Boundary,
        side: Side,
        evidence: Evidence,
        value: u64,
        has_value: bool,
        step: u64,
    ) void {
        self.answerWithClaim(boundary, side, evidence, .positive, value, has_value, .untyped, step);
    }

    /// Preserve an application's control-flow entry without treating it as a
    /// completed boundary. This is the safe bridge for tracepoints: a function
    /// can be entered and then return early, fault, or leave the state it was
    /// meant to publish untouched. The entry remains visible in reports while
    /// `Evidence.entered` stays below the substantiation threshold.
    pub fn noteApplicationEntry(self: *Ledger, boundary: Boundary, step: u64) void {
        self.answer(boundary, .application, .entered, 0, false, step);
    }

    /// State a positive answer whose numeric unit is explicit. Boolean-only
    /// callers can use `answer`; production counters should use this form so
    /// unrelated values cannot silently become corroboration.
    pub fn answerWithDomain(
        self: *Ledger,
        boundary: Boundary,
        side: Side,
        evidence: Evidence,
        value: u64,
        has_value: bool,
        value_domain: ValueDomain,
        step: u64,
    ) void {
        self.answerWithClaim(boundary, side, evidence, .positive, value, has_value, value_domain, step);
    }

    /// Record a bounded negative observation. This means the harness inspected
    /// the current causal frontier and found no instance of the boundary; it
    /// does not mean the application can never reach the event later.
    pub fn answerAbsent(
        self: *Ledger,
        boundary: Boundary,
        side: Side,
        value_domain: ValueDomain,
        step: u64,
    ) void {
        self.answerWithClaim(boundary, side, .observed, .negative, 0, true, value_domain, step);
    }

    fn answerWithClaim(
        self: *Ledger,
        boundary: Boundary,
        side: Side,
        evidence: Evidence,
        claim: Claim,
        value: u64,
        has_value: bool,
        value_domain: ValueDomain,
        step: u64,
    ) void {
        const entry = &self.records[@intFromEnum(boundary)];
        const slot = switch (side) {
            .application => &entry.application,
            .harness => &entry.harness,
        };
        if (evidence.rank() < slot.evidence.rank()) {
            // Never weaken a stronger observation with a later checkpoint.
            return;
        }

        // A negative answer is bounded by the checkpoint at which it was
        // observed.  It is valid to say "no dispatch through step 2.9B" and
        // later observe the title dispatch at step 2.95B; those observations
        // do not disagree.  Keeping the old negative in the live slot would
        // manufacture a result drift out of two observations with different
        // temporal horizons.  Same-step (or later) negative answers remain a
        // real conflict and are intentionally not relaxed.
        if (claim == .positive and evidence.substantiates()) {
            const other = switch (side) {
                .application => &entry.harness,
                .harness => &entry.application,
            };
            if (other.isNegative() and other.step < step) {
                other.* = .{};
                entry.superseded_negative_answers +|= 1;
            }
        }
        slot.evidence = evidence;
        slot.claim = claim;
        slot.step = step;
        slot.value = value;
        slot.has_value = has_value;
        slot.value_domain = if (has_value) value_domain else .untyped;
        if (entry.first_answer_step == 0 and evidence.substantiates())
            entry.first_answer_step = @max(step, 1);
    }

    pub fn notePrerequisites(self: *Ledger, boundary: Boundary, met: bool) void {
        self.records[@intFromEnum(boundary)].prerequisites_met = met;
    }

    pub fn setScope(self: *Ledger, scope: Scope, step: u64) void {
        if (!scope.checksArmed()) return;
        if (!self.scope_armed) {
            self.scope_armed = true;
            self.scope = scope;
            self.scope_start_step = step;
            return;
        }
        if (@intFromEnum(scope) > @intFromEnum(self.scope)) self.scope = scope;
    }

    pub fn scopeElapsed(self: *const Ledger, step: u64) u64 {
        if (!self.scope_armed) return 0;
        return step -| self.scope_start_step;
    }

    pub fn evaluate(self: *Ledger, step: u64) Summary {
        self.evaluations +|= 1;
        var findings = [_]Finding{.not_reached} ** boundary_count;
        var summary = Summary{
            .scope = self.scope,
            .scope_armed = self.scope_armed,
            .scope_elapsed_steps = self.scopeElapsed(step),
        };
        const elapsed = summary.scope_elapsed_steps;
        var index: u8 = 0;
        while (index < boundary_count) : (index += 1) {
            const boundary: Boundary = @enumFromInt(index);
            const entry = &self.records[index];
            const finding = contract.judge(.{
                .boundary = boundary,
                .application = entry.application,
                .harness = entry.harness,
                .step = elapsed,
                .scope = self.scope,
                .prerequisites_met = entry.prerequisites_met,
            });
            entry.observations +|= 1;
            if (entry.finding != finding) entry.last_change_step = step;
            entry.finding = finding;
            if (rank(finding) > rank(entry.best_finding)) entry.best_finding = finding;
            findings[index] = finding;
            if (entry.application.isNegative()) summary.bounded_negative += 1;
            if (entry.harness.isNegative()) summary.bounded_negative += 1;
            if (entry.superseded_negative_answers != 0) summary.superseded_negative += 1;
            switch (finding) {
                .not_reached => summary.not_reached += 1,
                .application_answered => {
                    summary.answered += 1;
                    summary.by_application += 1;
                },
                .harness_answered => {
                    summary.answered += 1;
                    summary.by_harness += 1;
                },
                .corroborated => {
                    summary.answered += 1;
                    summary.by_application += 1;
                    summary.by_harness += 1;
                    summary.corroborated += 1;
                },
                .diverged => {
                    summary.diverged += 1;
                    entry.divergences +|= 1;
                    self.divergences +|= 1;
                },
                .measurement_drift => {
                    summary.measurement_drifts += 1;
                    entry.divergences +|= 1;
                    self.divergences +|= 1;
                },
                .unsubstantiated => {
                    summary.unsubstantiated += 1;
                    if (boundary.rosetteMayAnswer()) summary.unsubstantiated_answerable += 1;
                },
            }
        }
        summary.problem = contract.firstProblem(findings);
        return summary;
    }

    pub fn fingerprint(self: *const Ledger) u64 {
        var hash: u64 = 0xB5AD_4ECE_DA10_1010;
        hash = mix(hash, @intFromEnum(self.scope));
        hash = mix(hash, @intFromBool(self.scope_armed));
        for (self.records) |entry| {
            hash = mix(hash, @intFromEnum(entry.finding));
            hash = mix(hash, @intFromEnum(entry.application.evidence));
            hash = mix(hash, @intFromEnum(entry.harness.evidence));
            hash = mix(hash, @intFromEnum(entry.application.claim));
            hash = mix(hash, @intFromEnum(entry.harness.claim));
            hash = mix(hash, @intFromEnum(entry.application.value_domain));
            hash = mix(hash, @intFromEnum(entry.harness.value_domain));
            hash = mix(hash, entry.superseded_negative_answers);
        }
        return hash;
    }
};

/// Ordering for "strongest finding so far". Corroboration outranks a single
/// answer; the two failures sit below `not_reached` so a boundary that has
/// diverged never reads as its best state.
fn rank(finding: Finding) u8 {
    return switch (finding) {
        .diverged, .measurement_drift => 0,
        .unsubstantiated => 1,
        .not_reached => 2,
        .harness_answered => 3,
        .application_answered => 4,
        .corroborated => 5,
    };
}

fn mix(hash: u64, value: u64) u64 {
    var next = hash ^ (value +% 0x9E37_79B9_7F4A_7C15 +% (hash << 6) +% (hash >> 2));
    next ^= next >> 33;
    next = next *% 0xFF51_AFD7_ED55_8CCD;
    next ^= next >> 29;
    return next;
}

// ---------------------------------------------------------------------------

test "an empty ledger reaches nothing and is clean" {
    var ledger = Ledger{};
    const summary = ledger.evaluate(0);
    try std.testing.expect(summary.clean());
    try std.testing.expectEqual(@as(usize, boundary_count), summary.not_reached);
    try std.testing.expect(summary.problem == null);
    try std.testing.expect(std.mem.indexOf(u8, summary.verdict(), "no boundary has been answered") != null);
}

test "Rosette answering for a boundary the application never reached is accepted" {
    var ledger = Ledger{};
    // Only this boundary is answered; the rest are deliberately left alone so
    // the assertion is about the answered one rather than about the set.
    ledger.answer(.ring_publication, .harness, .observed, 0x1FC9B000, true, 100);
    const summary = ledger.evaluate(contract.substantiation_grace_steps * 2);
    try std.testing.expectEqual(@as(usize, 1), summary.by_harness);
    const entry = ledger.record(.ring_publication);
    try std.testing.expectEqual(Finding.harness_answered, entry.finding);
    try std.testing.expect(entry.finding.acceptable());
    try std.testing.expect(entry.settled());
}

test "a boundary neither side answers past the grace is a hole" {
    var ledger = Ledger{};
    ledger.setScope(.application_execution, 0);
    const summary = ledger.evaluate(contract.substantiation_grace_steps);
    try std.testing.expect(!summary.clean());
    try std.testing.expectEqual(@as(usize, boundary_count), summary.unsubstantiated);
    try std.testing.expect(summary.problem != null);
}

test "substantiation grace begins at the first causal phase" {
    var ledger = Ledger{};
    const phase_start = 1_000_000;
    ledger.setScope(.application_execution, phase_start);
    const before_grace = ledger.evaluate(phase_start + contract.substantiation_grace_steps - 1);
    try std.testing.expectEqual(@as(usize, 0), before_grace.unsubstantiated);
    try std.testing.expectEqual(contract.substantiation_grace_steps - 1, before_grace.scope_elapsed_steps);
    const after_grace = ledger.evaluate(phase_start + contract.substantiation_grace_steps);
    try std.testing.expect(after_grace.unsubstantiated != 0);
    try std.testing.expectEqual(Scope.application_execution, after_grace.scope);
}

test "two sides disagreeing is reported ahead of a hole" {
    var ledger = Ledger{};
    // Everything is a hole except one boundary the two sides answered
    // differently. The divergence leads.
    ledger.answer(.presenter_entry, .application, .executed, 7, true, 10);
    ledger.answer(.presenter_entry, .harness, .observed, 9, true, 11);
    const summary = ledger.evaluate(contract.substantiation_grace_steps);
    try std.testing.expectEqual(@as(usize, 1), summary.diverged);
    try std.testing.expectEqual(Boundary.presenter_entry, summary.problem.?);
    try std.testing.expectEqual(@as(u64, 1), ledger.divergences);
}

test "presenter request corroborates before a frame completes" {
    var ledger = Ledger{};
    ledger.answerWithDomain(.presenter_entry, .application, .executed, 1, true, .presenter_requests, 10);
    // The host has received the request, but no drawable has completed yet.
    // Frame completion belongs to frame_presented and must not be required
    // before presenter_entry can be corroborated.
    ledger.answerWithDomain(.presenter_entry, .harness, .observed, 1, true, .presenter_requests, 10);
    const summary = ledger.evaluate(10);
    try std.testing.expectEqual(@as(usize, 1), summary.corroborated);
    try std.testing.expectEqual(@as(usize, 0), summary.diverged);
    try std.testing.expectEqual(Finding.corroborated, ledger.record(.presenter_entry).finding);
}

test "a stronger answer is never weakened by a later weaker one" {
    var ledger = Ledger{};
    ledger.answer(.command_processor, .application, .executed, 0, false, 10);
    ledger.answer(.command_processor, .application, .none, 0, false, 20);
    try std.testing.expectEqual(Evidence.executed, ledger.record(.command_processor).application.evidence);
    try std.testing.expectEqual(@as(u64, 10), ledger.record(.command_processor).application.step);
}

test "an application entry remains visible without answering the boundary" {
    var ledger = Ledger{};
    ledger.setScope(.application_execution, 0);
    ledger.noteApplicationEntry(.ring_publication, 100);
    ledger.answerAbsent(.ring_publication, .harness, .ring_advances, 100);
    const summary = ledger.evaluate(100);
    const entry = ledger.record(.ring_publication);
    try std.testing.expectEqual(Evidence.entered, entry.application.evidence);
    try std.testing.expect(!entry.application.substantiates());
    try std.testing.expectEqual(Finding.harness_answered, entry.finding);
    try std.testing.expectEqual(@as(usize, 0), summary.diverged);
}

test "a bounded negative answer closes a missing event" {
    var ledger = Ledger{};
    ledger.setScope(.application_execution, 0);
    var boundary_index: u8 = 0;
    while (boundary_index < boundary_count) : (boundary_index += 1) {
        ledger.notePrerequisites(@enumFromInt(boundary_index), false);
    }
    ledger.notePrerequisites(.ring_publication, true);
    ledger.answerAbsent(.ring_publication, .harness, .ring_advances, 100);
    const summary = ledger.evaluate(contract.substantiation_grace_steps * 2);
    const entry = ledger.record(.ring_publication);
    try std.testing.expectEqual(Finding.harness_answered, entry.finding);
    try std.testing.expect(entry.harness.isNegative());
    try std.testing.expectEqual(@as(usize, 1), summary.bounded_negative);
    try std.testing.expectEqual(@as(usize, 0), summary.unsubstantiated_answerable);
}

test "a later positive observation replaces a bounded negative answer" {
    var ledger = Ledger{};
    ledger.setScope(.application_execution, 0);
    ledger.answerAbsent(.command_processor, .harness, .pm4_packets, 100);
    ledger.answerWithDomain(.command_processor, .harness, .observed, 3, true, .pm4_packets, 200);
    const answer = ledger.record(.command_processor).harness;
    try std.testing.expect(!answer.isNegative());
    try std.testing.expectEqual(@as(u64, 3), answer.value);
    try std.testing.expectEqual(@as(u64, 100), ledger.record(.command_processor).first_answer_step);
}

test "a later application event supersedes an earlier harness absence" {
    var ledger = Ledger{};
    ledger.setScope(.gpu_activity, 0);

    // The harness checked the interrupt frontier before the guest's vblank
    // producer reached the callback.  The negative is true through step 100,
    // but it must not remain a second live account after the application
    // dispatches at step 200.
    ledger.answerAbsent(.interrupt_dispatch, .harness, .interrupt_dispatches, 100);
    ledger.answerWithDomain(.interrupt_dispatch, .application, .observed, 3, true, .interrupt_dispatches, 200);

    const before_evaluation = ledger.record(.interrupt_dispatch);
    try std.testing.expectEqual(Evidence.none, before_evaluation.harness.evidence);
    try std.testing.expectEqual(@as(u64, 1), before_evaluation.superseded_negative_answers);
    try std.testing.expectEqual(@as(u64, 100), before_evaluation.first_answer_step);

    const summary = ledger.evaluate(200);
    try std.testing.expectEqual(@as(usize, 1), summary.by_application);
    try std.testing.expectEqual(@as(usize, 0), summary.diverged);
    try std.testing.expectEqual(@as(usize, 1), summary.superseded_negative);
    try std.testing.expectEqual(Finding.application_answered, ledger.record(.interrupt_dispatch).finding);
}

test "a same-step absence remains a strict divergence" {
    var ledger = Ledger{};
    ledger.setScope(.gpu_activity, 0);
    ledger.answerAbsent(.interrupt_dispatch, .harness, .interrupt_dispatches, 200);
    ledger.answerWithDomain(.interrupt_dispatch, .application, .observed, 1, true, .interrupt_dispatches, 200);

    const summary = ledger.evaluate(200);
    try std.testing.expectEqual(@as(usize, 1), summary.diverged);
    try std.testing.expectEqual(@as(u64, 0), ledger.record(.interrupt_dispatch).superseded_negative_answers);
}

test "a later harness absence is not excused by an earlier application event" {
    var ledger = Ledger{};
    ledger.setScope(.gpu_activity, 0);
    ledger.answerWithDomain(.interrupt_dispatch, .application, .observed, 1, true, .interrupt_dispatches, 200);
    ledger.answerAbsent(.interrupt_dispatch, .harness, .interrupt_dispatches, 300);

    const summary = ledger.evaluate(300);
    try std.testing.expectEqual(@as(usize, 1), summary.diverged);
    try std.testing.expectEqual(@as(u64, 0), ledger.record(.interrupt_dispatch).superseded_negative_answers);
}

test "a positive application event and explicit host absence remain a divergence" {
    var ledger = Ledger{};
    ledger.setScope(.application_execution, 0);
    ledger.answer(.ring_publication, .application, .executed, 1, true, 200);
    ledger.answerAbsent(.ring_publication, .harness, .ring_advances, 200);
    const summary = ledger.evaluate(200);
    try std.testing.expectEqual(@as(usize, 1), summary.diverged);
    try std.testing.expectEqual(Boundary.ring_publication, summary.problem.?);
}

test "the best finding survives a boundary falling silent" {
    var ledger = Ledger{};
    ledger.answer(.frame_presented, .application, .executed, 1, true, 10);
    ledger.answer(.frame_presented, .harness, .executed, 1, true, 10);
    _ = ledger.evaluate(1000);
    try std.testing.expectEqual(Finding.corroborated, ledger.record(.frame_presented).best_finding);
    // A later disagreement changes the current finding, not the best one.
    ledger.answer(.frame_presented, .harness, .executed, 2, true, 20);
    _ = ledger.evaluate(2000);
    try std.testing.expectEqual(Finding.diverged, ledger.record(.frame_presented).finding);
    try std.testing.expectEqual(Finding.corroborated, ledger.record(.frame_presented).best_finding);
}

test "an unmet prerequisite keeps a downstream zero out of the finding list" {
    var ledger = Ledger{};
    var index: u8 = 0;
    while (index < boundary_count) : (index += 1) {
        ledger.notePrerequisites(@enumFromInt(index), false);
    }
    const summary = ledger.evaluate(contract.substantiation_grace_steps * 10);
    try std.testing.expect(summary.clean());
    try std.testing.expectEqual(@as(usize, boundary_count), summary.not_reached);
}

test "a first answer step is recorded once and never moves" {
    var ledger = Ledger{};
    ledger.answer(.swap_decode, .harness, .observed, 0, false, 500);
    ledger.answer(.swap_decode, .harness, .executed, 0, false, 900);
    try std.testing.expectEqual(@as(u64, 500), ledger.record(.swap_decode).first_answer_step);
}

test "the fingerprint moves only when an answer or a finding changes" {
    var ledger = Ledger{};
    _ = ledger.evaluate(100);
    const first = ledger.fingerprint();
    _ = ledger.evaluate(200);
    try std.testing.expectEqual(first, ledger.fingerprint());
    ledger.answer(.interrupt_dispatch, .harness, .observed, 0, false, 300);
    _ = ledger.evaluate(300);
    try std.testing.expect(ledger.fingerprint() != first);
}

// The reading the observed run produced: every armed tracepoint unentered,
// which is only a defect where Rosette also has nothing to say.
test "NEVER ENTERED with a Rosette answer is not a defect" {
    var ledger = Ledger{};
    ledger.setScope(.application_execution, 0);
    // Xenia's instruction pointer reached none of them.
    // Rosette observed the ring publication and the PM4 stream itself.
    ledger.answer(.ring_publication, .harness, .observed, 1, true, 100);
    ledger.answer(.command_processor, .harness, .observed, 72, true, 100);
    ledger.answer(.frame_presented, .harness, .executed, 62, true, 100);
    // Prerequisites for the swap chain do not hold: the title never requested
    // one, so the zeros below it belong to the request, not to the decoder.
    ledger.notePrerequisites(.swap_decode, false);
    ledger.notePrerequisites(.presenter_entry, false);
    ledger.notePrerequisites(.render_target, false);
    ledger.notePrerequisites(.interrupt_dispatch, false);
    const summary = ledger.evaluate(contract.substantiation_grace_steps * 2);
    // The swap request is still the application's positive event, but the
    // older test intentionally leaves it unanswered to prove the raw contract
    // still catches a missing producer claim. Runtime code now closes this
    // absence explicitly at an armed observation frontier.
    try std.testing.expectEqual(@as(usize, 1), summary.unsubstantiated);
    try std.testing.expectEqual(Boundary.swap_request, summary.problem.?);
    try std.testing.expectEqual(@as(usize, 3), summary.by_harness);
    try std.testing.expectEqual(@as(usize, 0), summary.by_application);
    try std.testing.expectEqual(@as(usize, 1), summary.unsubstantiated_answerable);
    try std.testing.expect(std.mem.indexOf(u8, summary.verdict(), "no account") != null);
}

test "an unanswered boundary remains a hole until a negative observation is supplied" {
    var ledger = Ledger{};
    ledger.setScope(.application_execution, 0);
    // Rosette answers several boundaries, but the remaining unanswered ones
    // are deliberately left raw. The contract does not invent a negative
    // answer on behalf of a caller that failed to publish one.
    ledger.answer(.ring_publication, .harness, .observed, 1, true, 10);
    ledger.answer(.command_processor, .harness, .observed, 72, true, 10);
    ledger.answer(.swap_decode, .harness, .observed, 1, true, 10);
    ledger.answer(.presenter_entry, .harness, .executed, 0, false, 10);
    ledger.answer(.interrupt_dispatch, .harness, .executed, 1, true, 10);
    ledger.answer(.frame_presented, .harness, .executed, 62, true, 10);
    const summary = ledger.evaluate(contract.substantiation_grace_steps * 2);
    try std.testing.expectEqual(@as(usize, 2), summary.unsubstantiated);
    try std.testing.expectEqual(@as(usize, 2), summary.unsubstantiated_answerable);
    try std.testing.expect(std.mem.indexOf(u8, summary.verdict(), "host observation frontier") != null);
}

test "an unanswered boundary Rosette could have given is Rosette's hole" {
    var ledger = Ledger{};
    ledger.setScope(.application_execution, 0);
    // Nothing answered at all: the ring publication is one Rosette models.
    const summary = ledger.evaluate(contract.substantiation_grace_steps * 2);
    try std.testing.expect(summary.unsubstantiated_answerable != 0);
    try std.testing.expect(std.mem.indexOf(u8, summary.verdict(), "host observation frontier") != null);
}
