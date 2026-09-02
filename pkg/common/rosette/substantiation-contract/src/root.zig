//! Which side can answer for a boundary, and whether the two agree.
//!
//! `NEVER ENTERED` on an armed tracepoint is not by itself a defect. It says
//! the hosted application's instruction pointer did not reach that address —
//! which is a problem only if *nobody* can answer the question that address was
//! going to answer. If Rosette models the same boundary, the run has an answer;
//! it just came from the other side.
//!
//! So the standard is not "did Xenia get there". It is:
//!
//!   * at least one side must be able to substantiate the boundary, and
//!   * when both can, they must agree.
//!
//! Those are different failures and they are kept apart. `unsubstantiated`
//! means the run has no account of the boundary at all and is proceeding on
//! nothing. `diverged` means it has two accounts that disagree, which is worse:
//! every downstream conclusion is drawn from whichever one the reader happened
//! to look at.
//!
//! During bring-up Rosette is expected to be answering for most of this. That
//! is the intended shape, not a degraded one — it is what "Rosette hosts the
//! application" means before the application is stable. The report says which
//! side answered so the balance is visible as it shifts. Once the causal scope
//! is armed, Rosette may also answer negatively at a bounded observation
//! frontier; this closes a known zero without claiming that the guest event
//! occurred or can never occur later.

const std = @import("std");

pub const schema_version: u16 = 3;

/// Causal phase for boundary accountability.
///
/// A process can spend a very long time loading, translating, or waiting for
/// the hosted title before it reaches any graphics boundary.  An unanswered
/// future boundary during that phase is not an unsubstantiated boundary: it is
/// not applicable yet.  Once guest execution (or GPU activity) is observed,
/// the boundary ledger becomes strict and its grace clock starts there rather
/// than at process creation.
pub const Scope = enum(u8) {
    pre_application,
    application_execution,
    gpu_activity,

    pub fn label(self: Scope) []const u8 {
        return switch (self) {
            .pre_application => "pre-application",
            .application_execution => "application-execution",
            .gpu_activity => "gpu-activity",
        };
    }

    pub fn checksArmed(self: Scope) bool {
        return self != .pre_application;
    }
};

/// A boundary the run needs an answer for.
///
/// Each is a question, not a code path: "was the ring published", "did a swap
/// reach the command processor". Either side may answer, and the boundary does
/// not care how.
pub const Boundary = enum(u8) {
    /// The guest's write pointer publication reached the ring.
    ring_publication,
    /// The command processor consumed a PM4 stream.
    command_processor,
    /// A swap request was encoded.
    swap_request,
    /// The XE_SWAP packet decoder ran.
    swap_decode,
    /// The presenter was asked to put a frame up.
    presenter_entry,
    /// The GPU interrupt callback was dispatched.
    interrupt_dispatch,
    /// A render target was programmed.
    render_target,
    /// A frame reached the window.
    frame_presented,

    pub fn label(self: Boundary) []const u8 {
        return switch (self) {
            .ring_publication => "ring-publication",
            .command_processor => "command-processor",
            .swap_request => "swap-request",
            .swap_decode => "swap-decode",
            .presenter_entry => "presenter-entry",
            .interrupt_dispatch => "interrupt-dispatch",
            .render_target => "render-target",
            .frame_presented => "frame-presented",
        };
    }

    /// What the boundary is being asked, in the words a reader needs when the
    /// answer is missing from both sides.
    pub fn question(self: Boundary) []const u8 {
        return switch (self) {
            .ring_publication => "has anything published a command span into the ring",
            .command_processor => "has anything consumed a PM4 stream",
            .swap_request => "has anything requested a swap",
            .swap_decode => "has anything decoded an XE_SWAP packet",
            .presenter_entry => "has anything asked a presenter for a frame",
            .interrupt_dispatch => "has anything dispatched the GPU interrupt callback",
            .render_target => "has anything programmed a render target",
            .frame_presented => "has any frame reached the window",
        };
    }

    /// Whether Rosette is expected to be able to answer this at all.
    ///
    /// Rosette can observe every boundary, including an explicit negative
    /// result ("nothing has happened through the current observation
    /// frontier"). Observation is not origination: a negative answer for a
    /// swap request or render-target program does not create either one.
    pub fn rosetteMayAnswer(self: Boundary) bool {
        _ = self;
        return true;
    }

    /// Whether Rosette may originate a positive guest-owned event for this
    /// boundary. This remains separate from `rosetteMayAnswer`: the harness can
    /// prove that a title has not requested a swap without fabricating a swap
    /// request. The current contract does not grant that origination authority
    /// for any Xenia boundary.
    pub fn rosetteMayOriginate(self: Boundary) bool {
        return switch (self) {
            .swap_request, .render_target => false,
            else => false,
        };
    }

    /// An armed causal scope gives Rosette a bounded observation frontier. At
    /// that frontier an absent event is a real observation, not an inference;
    /// before it, there is no meaningful negative answer to publish.
    pub fn rosetteMayCloseAsAbsent(self: Boundary, scope: Scope) bool {
        return self.rosetteMayAnswer() and scope.checksArmed();
    }

    /// The canonical counter domain Rosette uses when it closes this boundary
    /// as absent. Keeping this mapping in the package prevents a runtime
    /// observer from accidentally comparing a frame count with a packet count.
    pub fn observationDomain(self: Boundary) ValueDomain {
        return switch (self) {
            .ring_publication => .ring_advances,
            .command_processor => .pm4_packets,
            .swap_request => .swap_requests,
            .swap_decode => .xe_swap_packets,
            .presenter_entry => .presenter_requests,
            .interrupt_dispatch => .interrupt_dispatches,
            .render_target => .render_target_state,
            .frame_presented => .window_presentations,
        };
    }
};

pub const boundary_count: usize = @typeInfo(Boundary).@"enum".fields.len;

/// How a side came to its answer, ranked. A side that only inferred an answer
/// has not substantiated the boundary — it has restated an expectation. An
/// entry is retained as useful control-flow evidence, but it is deliberately
/// below `observed`: entering a producer, decoder, or presenter is not proof
/// that the operation completed or changed the state its boundary names.
pub const Evidence = enum(u8) {
    /// Nothing was observed.
    none,
    /// Derived from another fact rather than seen.
    inferred,
    /// The instruction pointer reached an entry point, but no completion or
    /// state-changing effect has been observed yet. This is diagnostic
    /// evidence only and must not close a causal boundary.
    entered,
    /// Read out of memory or a ledger this side owns.
    observed,
    /// The operation ran to completion or its state-changing effect was
    /// observed. Function entry alone is not this level of evidence.
    executed,

    pub fn label(self: Evidence) []const u8 {
        return switch (self) {
            .none => "none",
            .inferred => "inferred",
            .entered => "entered",
            .observed => "observed",
            .executed => "executed",
        };
    }

    pub fn rank(self: Evidence) u8 {
        return @intFromEnum(self);
    }

    /// Whether this is enough to say the side answered. An inference is not:
    /// it is the shape of a stale claim, and this codebase has been misled by
    /// one more than once.
    pub fn substantiates(self: Evidence) bool {
        return self.rank() >= Evidence.observed.rank();
    }
};

/// The polarity of an observed answer.
///
/// `positive` preserves the original answer semantics: the side observed or
/// executed the boundary. `negative` is an explicit, bounded absence claim:
/// the side observed the current frontier and found zero instances. It never
/// means that the event can never happen later. Keeping this separate from
/// `value == 0` prevents a zero counter from being mistaken for an unexamined
/// boundary.
pub const Claim = enum(u8) {
    positive,
    negative,

    pub fn label(self: Claim) []const u8 {
        return switch (self) {
            .positive => "positive",
            .negative => "negative",
        };
    }
};

/// The semantic unit carried by an answer's optional numeric value.
///
/// A boundary can be answered by two independently owned ledgers, but their
/// counters are only comparable when they count the same thing. A successful
/// `vkQueuePresentKHR` request, a completed window presentation, and a PM4
/// packet are all valid observations; none is interchangeable merely because
/// each fits in a `u64`. `.untyped` is retained for boolean answers and for
/// older callers that intentionally do not expose a numeric unit. If both
/// sides provide values, an untyped value is not allowed to corroborate a
/// typed one.
pub const ValueDomain = enum(u8) {
    untyped,
    ring_advances,
    pm4_packets,
    swap_requests,
    xe_swap_packets,
    presenter_requests,
    interrupt_dispatches,
    render_target_state,
    window_presentations,

    pub fn label(self: ValueDomain) []const u8 {
        return switch (self) {
            .untyped => "untyped",
            .ring_advances => "ring-advances",
            .pm4_packets => "pm4-packets",
            .swap_requests => "swap-requests",
            .xe_swap_packets => "xe-swap-packets",
            .presenter_requests => "presenter-requests",
            .interrupt_dispatches => "interrupt-dispatches",
            .render_target_state => "render-target-state",
            .window_presentations => "window-presentations",
        };
    }
};

/// One side's answer to a boundary.
pub const Answer = struct {
    evidence: Evidence = .none,
    claim: Claim = .positive,
    /// The value the side is reporting, when the boundary carries one. Compared
    /// against the other side only when both substantiate.
    value: u64 = 0,
    /// Whether the side reports a value at all. A boundary answered with "yes
    /// it happened" and no value is still an answer; it just cannot be
    /// cross-checked.
    has_value: bool = false,
    /// The semantic unit of `value`. This is carried with the answer rather
    /// than inferred from the boundary because different producers can answer
    /// the same causal boundary with different measurements.
    value_domain: ValueDomain = .untyped,
    step: u64 = 0,

    pub fn substantiates(self: Answer) bool {
        return self.evidence.substantiates();
    }

    pub fn isNegative(self: Answer) bool {
        return self.substantiates() and self.claim == .negative;
    }
};

pub const Finding = enum(u8) {
    /// Neither side has looked yet, and the run has not reached a point where
    /// either would have. Says nothing.
    not_reached,
    /// Only the hosted application answered.
    application_answered,
    /// Only Rosette answered. The expected shape during bring-up.
    harness_answered,
    /// Both answered and agree.
    corroborated,
    /// Both answered and disagree. The worst outcome: two accounts of one fact.
    diverged,
    /// Both answered with numeric values, but the values describe different
    /// measurement domains. This is a contract/instrumentation failure, not a
    /// valid disagreement to resolve by choosing one side.
    measurement_drift,
    /// Neither side can answer, and at least one of them should have been able
    /// to by now. The run is proceeding on no account of this boundary at all.
    unsubstantiated,

    pub fn label(self: Finding) []const u8 {
        return switch (self) {
            .not_reached => "not-reached",
            .application_answered => "application-answered",
            .harness_answered => "harness-answered",
            .corroborated => "corroborated",
            .diverged => "diverged",
            .measurement_drift => "measurement-drift",
            .unsubstantiated => "unsubstantiated",
        };
    }

    /// Whether the run may proceed on this boundary.
    pub fn acceptable(self: Finding) bool {
        return switch (self) {
            .not_reached, .application_answered, .harness_answered, .corroborated => true,
            .diverged, .measurement_drift, .unsubstantiated => false,
        };
    }

    pub fn meaning(self: Finding) []const u8 {
        return switch (self) {
            .not_reached => "neither side has been asked yet; the run has not arrived here and this zero names nothing on its own",
            .application_answered => "the hosted application substantiated this itself; Rosette did not need to answer for it",
            .harness_answered => "Rosette answered for the application. During bring-up this is the intended shape and not a degraded one; it is what hosting means before the application is stable",
            .corroborated => "both sides answered and agree, which is the only state in which a value from either one can be quoted without saying which",
            .diverged => "both sides answered and disagree; every conclusion drawn downstream depends on which account the reader happened to read, and neither is marked",
            .measurement_drift => "both sides answered with values from different measurement domains; the numbers are not comparable and the boundary must not be allowed to pass until the producers report the same unit",
            .unsubstantiated => "neither side can answer and at least one should have been able to by now; the run is proceeding with no account of this boundary at all",
        };
    }
};

/// Whether the run has been going long enough that an unanswered boundary is a
/// finding rather than an ordering.
///
/// The same discipline the rest of the strictness work follows: a boundary
/// nobody has reached at step zero says nothing, and reporting it as a hole
/// would fire on every healthy bring-up.
pub const substantiation_grace_steps: u64 = 500_000_000;

pub const Reading = struct {
    boundary: Boundary,
    application: Answer = .{},
    harness: Answer = .{},
    /// Steps since the causal scope became accountable, so grace can be
    /// applied without making startup translation responsible for future GPU
    /// events.
    step: u64 = 0,
    scope: Scope = .pre_application,
    /// Whether the boundary's prerequisites hold, so an absent answer is about
    /// this boundary rather than about one above it.
    prerequisites_met: bool = true,
};

pub fn judge(reading: Reading) Finding {
    const application = reading.application.substantiates();
    const harness = reading.harness.substantiates();

    if (application and harness) {
        if (reading.application.claim != reading.harness.claim) return .diverged;
        // Only comparable when both actually carry a value.
        if (reading.application.has_value and reading.harness.has_value and
            reading.application.value_domain != reading.harness.value_domain)
            return .measurement_drift;
        if (reading.application.has_value and reading.harness.has_value and
            reading.application.value != reading.harness.value) return .diverged;
        return .corroborated;
    }
    if (application) return .application_answered;
    if (harness) return .harness_answered;

    // Nobody answered. Whether that is a hole depends on whether anyone could
    // have by now.
    if (!reading.scope.checksArmed()) return .not_reached;
    if (!reading.prerequisites_met) return .not_reached;
    if (reading.step < substantiation_grace_steps) return .not_reached;
    return .unsubstantiated;
}

/// The boundary a report should lead with: a divergence before a hole, because
/// a divergence means the run has already drawn conclusions from one of two
/// disagreeing accounts.
pub fn firstProblem(findings: [boundary_count]Finding) ?Boundary {
    var index: u8 = 0;
    while (index < boundary_count) : (index += 1) {
        if (findings[index] == .measurement_drift) return @enumFromInt(index);
    }
    index = 0;
    while (index < boundary_count) : (index += 1) {
        if (findings[index] == .diverged) return @enumFromInt(index);
    }
    index = 0;
    while (index < boundary_count) : (index += 1) {
        if (findings[index] == .unsubstantiated) return @enumFromInt(index);
    }
    return null;
}

/// Every boundary states a question and a meaning, and no two share a label.
pub fn contractIsWellFormed() bool {
    var index: u8 = 0;
    while (index < boundary_count) : (index += 1) {
        const boundary: Boundary = @enumFromInt(index);
        if (boundary.label().len == 0 or boundary.question().len == 0) return false;
        var other: u8 = 0;
        while (other < boundary_count) : (other += 1) {
            if (other == index) continue;
            const compared: Boundary = @enumFromInt(other);
            if (std.mem.eql(u8, boundary.label(), compared.label())) return false;
        }
    }
    return true;
}

test "the contract is well formed" {
    try std.testing.expect(contractIsWellFormed());
}

test "a boundary nobody has reached yet is not a hole" {
    try std.testing.expectEqual(Finding.not_reached, judge(.{ .boundary = .ring_publication, .step = 0 }));
    try std.testing.expect(judge(.{ .boundary = .ring_publication, .step = 0 }).acceptable());
}

test "a boundary nobody can answer after the grace is a hole" {
    const finding = judge(.{
        .boundary = .ring_publication,
        .step = substantiation_grace_steps,
        .scope = .application_execution,
    });
    try std.testing.expectEqual(Finding.unsubstantiated, finding);
    try std.testing.expect(!finding.acceptable());
}

test "pre-application absence is not a hole regardless of wall-clock steps" {
    const finding = judge(.{
        .boundary = .ring_publication,
        .step = substantiation_grace_steps * 100,
        .scope = .pre_application,
    });
    try std.testing.expectEqual(Finding.not_reached, finding);
    try std.testing.expect(finding.acceptable());
}

test "an unmet prerequisite keeps a boundary out of the finding list" {
    // The zero belongs to the boundary above this one, not to this one.
    try std.testing.expectEqual(Finding.not_reached, judge(.{
        .boundary = .swap_decode,
        .step = substantiation_grace_steps * 10,
        .prerequisites_met = false,
    }));
}

test "Rosette answering for the application is an accepted shape" {
    const finding = judge(.{
        .boundary = .ring_publication,
        .step = substantiation_grace_steps * 4,
        .harness = .{ .evidence = .observed },
    });
    try std.testing.expectEqual(Finding.harness_answered, finding);
    try std.testing.expect(finding.acceptable());
}

test "the application answering for itself is an accepted shape" {
    const finding = judge(.{
        .boundary = .swap_request,
        .step = substantiation_grace_steps * 4,
        .application = .{ .evidence = .executed },
    });
    try std.testing.expectEqual(Finding.application_answered, finding);
    try std.testing.expect(finding.acceptable());
}

test "an inference is not an answer" {
    // The shape of a stale claim: a side restating an expectation.
    const finding = judge(.{
        .boundary = .command_processor,
        .step = substantiation_grace_steps * 2,
        .scope = .application_execution,
        .application = .{ .evidence = .inferred },
        .harness = .{ .evidence = .inferred },
    });
    try std.testing.expectEqual(Finding.unsubstantiated, finding);
}

test "an entry observation is not a completed boundary answer" {
    const finding = judge(.{
        .boundary = .ring_publication,
        .step = substantiation_grace_steps,
        .scope = .application_execution,
        .application = .{ .evidence = .entered, .claim = .positive },
        .harness = .{
            .evidence = .observed,
            .claim = .negative,
            .has_value = true,
            .value_domain = .ring_advances,
        },
    });
    try std.testing.expect(!Evidence.entered.substantiates());
    try std.testing.expectEqual("entered", Evidence.entered.label());
    try std.testing.expectEqual(Finding.harness_answered, finding);
}

test "both sides agreeing corroborates and both disagreeing diverges" {
    var reading = Reading{
        .boundary = .ring_publication,
        .step = 1000,
        .application = .{ .evidence = .executed, .value = 0x1FC9B000, .has_value = true, .value_domain = .ring_advances },
        .harness = .{ .evidence = .observed, .value = 0x1FC9B000, .has_value = true, .value_domain = .ring_advances },
    };
    try std.testing.expectEqual(Finding.corroborated, judge(reading));
    reading.harness.value = 0x1FC00000;
    const diverged = judge(reading);
    try std.testing.expectEqual(Finding.diverged, diverged);
    try std.testing.expect(!diverged.acceptable());
}

test "different numeric domains are measurement drift, not corroboration" {
    const finding = judge(.{
        .boundary = .frame_presented,
        .step = 1000,
        .application = .{ .evidence = .executed, .value = 1, .has_value = true, .value_domain = .presenter_requests },
        .harness = .{ .evidence = .executed, .value = 2, .has_value = true, .value_domain = .window_presentations },
    });
    try std.testing.expectEqual(Finding.measurement_drift, finding);
    try std.testing.expect(!finding.acceptable());
    try std.testing.expect(std.mem.indexOf(u8, finding.meaning(), "not comparable") != null);
}

test "an explicit negative observation is an answer, not not-reached" {
    const answer = Answer{
        .evidence = .observed,
        .claim = .negative,
        .has_value = true,
        .value_domain = .ring_advances,
    };
    try std.testing.expect(answer.substantiates());
    try std.testing.expect(answer.isNegative());
    try std.testing.expectEqual(Finding.harness_answered, judge(.{
        .boundary = .ring_publication,
        .step = substantiation_grace_steps * 2,
        .scope = .application_execution,
        .harness = answer,
    }));
}

test "two explicit negative observations corroborate" {
    const application = Answer{
        .evidence = .observed,
        .claim = .negative,
        .has_value = true,
        .value_domain = .pm4_packets,
    };
    const harness = application;
    try std.testing.expectEqual(Finding.corroborated, judge(.{
        .boundary = .command_processor,
        .application = application,
        .harness = harness,
    }));
}

test "a positive and negative observation diverge" {
    try std.testing.expectEqual(Finding.diverged, judge(.{
        .boundary = .ring_publication,
        .application = .{ .evidence = .executed, .claim = .positive },
        .harness = .{ .evidence = .observed, .claim = .negative },
    }));
}

test "two answers without values corroborate rather than diverge" {
    // "It happened" from both sides is agreement; there is nothing to compare.
    try std.testing.expectEqual(Finding.corroborated, judge(.{
        .boundary = .presenter_entry,
        .step = 1000,
        .application = .{ .evidence = .executed },
        .harness = .{ .evidence = .executed },
    }));
}

test "a divergence outranks a hole in the report" {
    var findings = [_]Finding{.not_reached} ** boundary_count;
    findings[@intFromEnum(Boundary.command_processor)] = .unsubstantiated;
    try std.testing.expectEqual(Boundary.command_processor, firstProblem(findings).?);
    findings[@intFromEnum(Boundary.presenter_entry)] = .diverged;
    try std.testing.expectEqual(Boundary.presenter_entry, firstProblem(findings).?);
}

test "an all-accepted set has no problem to report" {
    var findings = [_]Finding{.harness_answered} ** boundary_count;
    findings[0] = .corroborated;
    findings[1] = .application_answered;
    try std.testing.expect(firstProblem(findings) == null);
}

test "every boundary is observable while origination stays restricted" {
    try std.testing.expect(Boundary.swap_request.rosetteMayAnswer());
    try std.testing.expect(Boundary.render_target.rosetteMayAnswer());
    try std.testing.expect(!Boundary.swap_request.rosetteMayOriginate());
    try std.testing.expect(!Boundary.render_target.rosetteMayOriginate());
    try std.testing.expect(Boundary.ring_publication.rosetteMayAnswer());
    try std.testing.expect(Boundary.frame_presented.rosetteMayAnswer());
    try std.testing.expect(Boundary.ring_publication.rosetteMayCloseAsAbsent(.application_execution));
    try std.testing.expect(!Boundary.ring_publication.rosetteMayCloseAsAbsent(.pre_application));
    try std.testing.expectEqual(ValueDomain.xe_swap_packets, Boundary.swap_decode.observationDomain());
    try std.testing.expectEqual(ValueDomain.window_presentations, Boundary.frame_presented.observationDomain());
}
