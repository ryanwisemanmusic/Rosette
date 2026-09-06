//! Build-time policy for waits that cross the Rosette/Xenia boundary.
//!
//! A wait result is not one thing.  A timed poll, a ready-on-entry event, a
//! real blocked handoff, an open dependency, and a pair of threads spinning
//! through the same continuation all return through a wait-shaped API while
//! requiring different runtime treatment.  This package owns that vocabulary
//! and the safe actions associated with it.  Runtime ledgers supply the
//! evidence; they do not get to invent a wakeup policy independently.
//!
//! The important safety boundary is synthetic wakeups.  They are allowed only
//! for an explicitly opted-in POSIX condition-variable recheck whose mutex is
//! available and whose predicate is known to be safe to evaluate again.  A
//! guest semaphore, guest event, futex, join, or unknown object is never
//! converted into a condition-variable wake by this policy.

const std = @import("std");

/// The object family matters more than its address.  An unknown address is
/// intentionally not treated as a POSIX condition variable just because the
/// host happens to represent it with one.
pub const ObjectKind = enum(u8) {
    unknown,
    guest_semaphore,
    guest_auto_reset_event,
    guest_manual_reset_event,
    posix_condvar,
    cpp_condvar,
    mutex,
    futex,
    thread_join,
    timer,
    io_completion,
    /// A guest Mutant: a kernel mutex with ownership and recursion. A wait on
    /// one *acquires* it, so consumption is well defined — unlike `mutex`,
    /// which is a host primitive Rosette owns rather than a guest object the
    /// title waits on.
    guest_mutant,
    /// A guest NotifyListener: the queue a title waits on for system
    /// notifications. Waiting consumes a queued notification.
    guest_notify_listener,
    /// An object type that carries no dispatcher header, so the guest cannot
    /// legally wait on it. Distinct from `unknown`: this is a recognised type
    /// in a place it cannot appear, which accuses the observer or the parse
    /// rather than asking for a new table entry.
    not_waitable,

    pub fn label(self: ObjectKind) []const u8 {
        return switch (self) {
            .unknown => "unknown",
            .guest_semaphore => "guest_semaphore",
            .guest_auto_reset_event => "guest_auto_reset_event",
            .guest_manual_reset_event => "guest_manual_reset_event",
            .posix_condvar => "posix_condvar",
            .cpp_condvar => "cpp_condvar",
            .mutex => "mutex",
            .futex => "futex",
            .thread_join => "thread_join",
            .timer => "timer",
            .io_completion => "io_completion",
            .guest_mutant => "guest_mutant",
            .guest_notify_listener => "guest_notify_listener",
            .not_waitable => "not_waitable",
        };
    }
};

/// The timeout's shape is part of the guest ABI contract. A finite manual-reset
/// event used as a polling boundary is not the same operation as an unbounded
/// dependency that can only finish after another thread signals it. Keeping
/// this classification in the package prevents each runtime ledger from
/// deciding independently whether a timeout is a completed guest operation or
/// a missing handoff.
pub const TimeoutClass = enum(u8) {
    /// No timeout evidence was supplied because the observation was not a
    /// timeout or came from a legacy line with no timing fields.
    none,
    unknown,
    /// A requested, short, finite timeout on a manual-reset guest event. This
    /// is the shape used by a guest polling loop: the timeout result is
    /// authoritative, but it is not a signal and must not be synthesized.
    bounded_poll,
    /// A finite deadline whose polling semantics were not proven.
    finite_deadline,
    /// A negative guest timeout, conventionally an infinite/relative wait.
    unbounded_wait,
    /// More than one incompatible timeout shape was observed for one object.
    mixed,

    pub fn label(self: TimeoutClass) []const u8 {
        return switch (self) {
            .none => "none",
            .unknown => "unknown",
            .bounded_poll => "bounded_poll",
            .finite_deadline => "finite_deadline",
            .unbounded_wait => "unbounded_wait",
            .mixed => "mixed",
        };
    }

    pub fn isBoundedPoll(self: TimeoutClass) bool {
        return self == .bounded_poll;
    }
};

/// Immutable timeout evidence supplied by the Xenia log bridge. `requested`
/// is deliberately separate from `known`: a result duration proves that the
/// host waited for some time, but it does not prove that the guest requested a
/// finite poll. The latter requires the pre-wait deadline (or an explicit
/// deadline on the result line).
pub const TimeoutEvidence = struct {
    timeout_ms: i64 = 0,
    timeout_known: bool = false,
    /// Whether `requested` came from the guest's timeout pointer (or an
    /// explicit result-field contract) rather than the default value. This is
    /// reporting provenance only; an unknown request must never be promoted
    /// to a bounded poll by a caller.
    requested_known: bool = false,
    requested: bool = false,
    object_kind: ObjectKind = .unknown,
    event_mode_known: bool = false,
    manual_reset: bool = false,
};

/// Maximum deadline that can be called a polling boundary without a separate
/// guest-specific contract. This is intentionally conservative: longer
/// finite waits remain finite deadlines and therefore retain the hard
/// repeated-timeout gate.
pub const bounded_poll_max_ms: i64 = 1000;

pub fn classifyTimeout(evidence: TimeoutEvidence) TimeoutClass {
    if (!evidence.timeout_known) return .unknown;
    if (evidence.timeout_ms < 0) return .unbounded_wait;
    if (evidence.requested and evidence.timeout_ms > 0 and
        evidence.timeout_ms <= bounded_poll_max_ms and
        evidence.object_kind == .guest_manual_reset_event and
        evidence.event_mode_known and evidence.manual_reset)
    {
        return .bounded_poll;
    }
    return .finite_deadline;
}

/// Independent progress supplied by the caller.  Unknown is not healthy:
/// without a progress witness a matched pair cannot be distinguished from a
/// livelock, so the policy holds it in evidence collection.
pub const Progress = enum(u8) {
    unknown,
    flat,
    advanced,

    pub fn label(self: Progress) []const u8 {
        return switch (self) {
            .unknown => "unknown",
            .flat => "flat",
            .advanced => "advanced",
        };
    }
};

pub const NotifierState = enum(u8) {
    none,
    running,
    parked,
    terminated,
    unknown,

    pub fn label(self: NotifierState) []const u8 {
        return switch (self) {
            .none => "none",
            .running => "running",
            .parked => "parked",
            .terminated => "terminated",
            .unknown => "unknown",
        };
    }
};

/// The address printed beside a wait is meaningful only together with the
/// machine whose control flow it names.  Rosette's translated x86 RIP, Xenia's
/// optional PowerPC source PC, and a native return address can all be non-zero
/// at the same instant while referring to different address spaces.
pub const PcDomain = enum(u8) {
    unknown,
    xenia_guest_ppc,
    rosette_translated_x86,
    native_host,

    pub fn label(self: PcDomain) []const u8 {
        return switch (self) {
            .unknown => "unknown",
            .xenia_guest_ppc => "xenia_guest_ppc",
            .rosette_translated_x86 => "rosette_translated_x86",
            .native_host => "native_host",
        };
    }

    pub fn guidance(self: PcDomain) []const u8 {
        return switch (self) {
            .unknown => "the address has no declared machine or address-space provenance",
            .xenia_guest_ppc => "this address names Xenia's PowerPC guest stream",
            .rosette_translated_x86 => "this address names Rosette's translated x86 execution stream, not the PowerPC guest",
            .native_host => "this address names a native host call site, not guest control flow",
        };
    }
};

/// How the producer established a PC.  A non-zero value seeded by a function
/// entry is useful for locating a breadcrumb, but it is not instruction-level
/// continuation evidence.  `tracked` is reserved for Xenia's source-offset
/// instrumentation; `direct` is used for Rosette/native execution state that
/// the owning runtime controls directly.
pub const PcQuality = enum(u8) {
    unavailable,
    seeded,
    tracked,
    direct,

    pub fn label(self: PcQuality) []const u8 {
        return switch (self) {
            .unavailable => "unavailable",
            .seeded => "seeded",
            .tracked => "tracked",
            .direct => "direct",
        };
    }

    pub fn usable(self: PcQuality) bool {
        return self == .tracked or self == .direct;
    }
};

/// Address provenance is part of the evidence contract, not presentation
/// formatting.  Two equal integers are comparable only when both sides have a
/// usable quality and belong to the same address domain.
pub const PcEvidence = struct {
    address: u64 = 0,
    domain: PcDomain = .unknown,
    quality: PcQuality = .unavailable,

    pub fn usable(self: PcEvidence) bool {
        return self.address != 0 and self.quality.usable();
    }

    pub fn comparableWith(self: PcEvidence, other: PcEvidence) bool {
        return self.usable() and other.usable() and self.domain == other.domain;
    }

    pub fn provesGuestControlFlow(self: PcEvidence) bool {
        return self.usable() and self.domain == .xenia_guest_ppc;
    }
};

/// The minimum control-flow evidence Rosette accepts after a wait returns.
///
/// This is deliberately a vocabulary, not a recovery decision.  A wait can
/// return successfully and still immediately re-enter the same wait site.  A
/// different observed site is useful evidence that control flow moved, but it
/// is not by itself permission to claim GPU progress or synthesize a signal.
pub const ContinuationState = enum(u8) {
    pending,
    same_site,
    transitioned,
    observed_without_pc,
    observed_untrusted_pc,
    incomparable_pc,
    unobserved,
    out_of_order,

    pub fn label(self: ContinuationState) []const u8 {
        return switch (self) {
            .pending => "pending",
            .same_site => "same_site",
            .transitioned => "transitioned",
            .observed_without_pc => "observed_without_pc",
            .observed_untrusted_pc => "observed_untrusted_pc",
            .incomparable_pc => "incomparable_pc",
            .unobserved => "unobserved",
            .out_of_order => "out_of_order",
        };
    }

    pub fn guidance(self: ContinuationState) []const u8 {
        return switch (self) {
            .pending => "the wait returned but no later guest activity has been observed yet",
            .same_site => "the first later activity was at the same comparable execution site; this is re-entry evidence, not independent progress",
            .transitioned => "the first later activity was at a different comparable execution site; this proves domain-local control-flow movement only",
            .observed_without_pc => "later guest activity was observed, but no usable PC was available to compare sites",
            .observed_untrusted_pc => "later activity was observed, but at least one PC was seeded or otherwise untrusted, so it cannot prove continuation",
            .incomparable_pc => "both PCs were present but belonged to different address domains, so they cannot prove one control-flow stream",
            .unobserved => "a later wait completion arrived before any continuation activity was observed",
            .out_of_order => "an activity carried a step not newer than the wait completion and was not used as continuation evidence",
        };
    }

    /// Only a different, ordered guest PC is a control-flow transition. Even
    /// that remains weaker than an independent graphics-progress witness.
    pub fn provesControlFlowTransition(self: ContinuationState) bool {
        return self == .transitioned;
    }
};

/// Temporal evidence for a blocked wait. Matching counters alone cannot prove
/// that a signal released a particular waiter; this vocabulary records only
/// what the event stream can establish without guessing a pairing.
pub const HandoffOrder = enum(u8) {
    unknown,
    signal_before_return,
    return_without_prior_signal,
    mixed,

    pub fn label(self: HandoffOrder) []const u8 {
        return switch (self) {
            .unknown => "unknown",
            .signal_before_return => "signal_before_return",
            .return_without_prior_signal => "return_without_prior_signal",
            .mixed => "mixed",
        };
    }

    pub fn guidance(self: HandoffOrder) []const u8 {
        return switch (self) {
            .unknown => "no blocked wait has enough temporal evidence to classify the handoff",
            .signal_before_return => "at least one blocked wait returned after an observed signal on the same canonical object",
            .return_without_prior_signal => "a blocked wait returned without a prior observed signal on the same canonical object",
            .mixed => "the object has both ordered and un-ordered blocked returns; aggregate counts must not be promoted to a single causal pairing",
        };
    }
};

pub const Severity = enum(u8) {
    observation,
    caution,
    fault,

    pub fn label(self: Severity) []const u8 {
        return switch (self) {
            .observation => "observation",
            .caution => "caution",
            .fault => "fault",
        };
    }
};

/// What the evidence says about one object at this instant.
pub const Classification = enum(u8) {
    unobserved,
    insufficient_evidence,
    ready_without_park,
    timeout_only,
    timeout_with_signal,
    open_wait,
    notifier_parked,
    orphan_wait,
    orphan_signal,
    handshake_progressing,
    handshake_stalled,
    identity_conflict,

    pub fn label(self: Classification) []const u8 {
        return switch (self) {
            .unobserved => "unobserved",
            .insufficient_evidence => "insufficient_evidence",
            .ready_without_park => "ready_without_park",
            .timeout_only => "timeout_only",
            .timeout_with_signal => "timeout_with_signal",
            .open_wait => "open_wait",
            .notifier_parked => "notifier_parked",
            .orphan_wait => "orphan_wait",
            .orphan_signal => "orphan_signal",
            .handshake_progressing => "handshake_progressing",
            .handshake_stalled => "handshake_stalled",
            .identity_conflict => "identity_conflict",
        };
    }

    pub fn guidance(self: Classification) []const u8 {
        return switch (self) {
            .unobserved => "no wait or signal evidence exists for this object",
            .insufficient_evidence => "the observed timing or progress evidence is incomplete; do not infer a wake or a healthy handoff",
            .ready_without_park => "the wait returned ready without proving that the caller parked; preserve the result but do not count it as a blocked handoff",
            .timeout_only => "all observed attempts expired without consuming a signal; keep the waiter on the authoritative deadline/signal path and do not synthesize a wake",
            .timeout_with_signal => "attempts expired while a signal was observed, but no wait consumed it; preserve the ordering ambiguity and do not claim a handoff",
            .open_wait => "a wait remains open without a completion witness; hold the dependent continuation until the owner or deadline supplies an authoritative result",
            .notifier_parked => "the observed notifier is parked as well; this is a producer-path lead, not permission to inject a guest wake",
            .orphan_wait => "a non-timeout wait has no observed notifier; locate the producer before allowing the dependent continuation to claim success",
            .orphan_signal => "a signal has no observed consumer; keep it as evidence of a producer path, not as proof that another object was released",
            .handshake_progressing => "matched waits and signals have an independent progress witness; the handoff is allowed to continue",
            .handshake_stalled => "matched waits and signals repeatedly return without independent progress; inspect the continuation and fault before hiding the livelock",
            .identity_conflict => "the same synchronization object has incompatible identities; stop before any wait or signal is attributed to the wrong object",
        };
    }

    pub fn isFinding(self: Classification) bool {
        return switch (self) {
            .handshake_stalled, .orphan_wait, .identity_conflict => true,
            .unobserved,
            .insufficient_evidence,
            .ready_without_park,
            .timeout_only,
            .timeout_with_signal,
            .open_wait,
            .notifier_parked,
            .orphan_signal,
            .handshake_progressing,
            => false,
        };
    }
};

/// The only runtime actions this policy can authorize.  There is no generic
/// "wake" action: a caller must go through `spuriousWakeDecision` and satisfy
/// the POSIX-only preconditions below.
pub const Action = enum(u8) {
    observe_only,
    continue_execution,
    await_authoritative_signal,
    await_deadline,
    refresh_runnable_set,
    report_and_hold,
    fault_before_resume,
    refuse_synthetic_wake,

    pub fn label(self: Action) []const u8 {
        return switch (self) {
            .observe_only => "observe_only",
            .continue_execution => "continue_execution",
            .await_authoritative_signal => "await_authoritative_signal",
            .await_deadline => "await_deadline",
            .refresh_runnable_set => "refresh_runnable_set",
            .report_and_hold => "report_and_hold",
            .fault_before_resume => "fault_before_resume",
            .refuse_synthetic_wake => "refuse_synthetic_wake",
        };
    }
};

/// Thresholds are data so a host route can audit the policy without changing
/// its decision code.  The defaults match the existing wait-graph maturity
/// and run-integrity timeout gates.
pub const Config = struct {
    minimum_handshake_sample: u64 = 8,
    timeout_fault_threshold: u64 = 32,
};

/// A snapshot assembled by the runtime ledger.  `waits` includes every
/// attempt; `successful_waits` includes only ready-on-entry and blocked results
/// with explicit timing evidence.  Unknown and timed-out attempts therefore
/// cannot silently become successful handoffs.
pub const Evidence = struct {
    object_kind: ObjectKind = .unknown,
    timeout_class: TimeoutClass = .none,
    waits: u64 = 0,
    signals: u64 = 0,
    successful_waits: u64 = 0,
    timed_out_waits: u64 = 0,
    blocked_successes: u64 = 0,
    ready_on_entry: u64 = 0,
    unknown_timing: u64 = 0,
    waiter_count: u64 = 0,
    notifier_count: u64 = 0,
    notifications: u64 = 0,
    notifier_state: NotifierState = .unknown,
    progress: Progress = .unknown,
    same_site_reentries: u64 = 0,
    site_transitions: u64 = 0,
    open_wait: bool = false,
    identity_conflict: bool = false,
    finite_deadline: bool = false,
};

pub const Decision = struct {
    classification: Classification,
    action: Action,
    severity: Severity,
    may_resume: bool,
    may_synthesize_wake: bool,
    requires_fault: bool,

    pub fn label(self: Decision) []const u8 {
        return self.classification.label();
    }

    pub fn guidance(self: Decision) []const u8 {
        return self.classification.guidance();
    }
};

fn decision(
    classification: Classification,
    action: Action,
    severity: Severity,
    may_resume: bool,
) Decision {
    return .{
        .classification = classification,
        .action = action,
        .severity = severity,
        .may_resume = may_resume,
        .may_synthesize_wake = false,
        .requires_fault = severity == .fault,
    };
}

/// Classify a snapshot without changing runtime state.  In particular, this
/// function never turns a timeout into a successful wait and never treats
/// unknown progress as advancement.
pub fn decide(evidence: Evidence, config: Config) Decision {
    if (evidence.identity_conflict) {
        return decision(.identity_conflict, .fault_before_resume, .fault, false);
    }

    if (evidence.waits == 0 and evidence.signals == 0 and !evidence.open_wait) {
        return decision(.unobserved, .observe_only, .observation, true);
    }

    // An open dependency takes precedence over historical activity.  A
    // caller cannot resume merely because an earlier attempt on the same
    // object succeeded.
    if (evidence.open_wait) {
        if (evidence.notifier_state == .parked) {
            return decision(.notifier_parked, .report_and_hold, .caution, false);
        }
        return decision(.open_wait, .await_authoritative_signal, .caution, false);
    }

    // Timed waits are polling/deadline observations, not parked consumers.
    // Keep them out of the orphan-wait and handshake counts.  The caller's
    // stricter run-integrity gate may fault after enough repeated expiries.
    if (evidence.timed_out_waits != 0 and evidence.successful_waits == 0) {
        const timed_out_class = if (evidence.signals == 0) Classification.timeout_only else Classification.timeout_with_signal;
        // A finite, requested manual-reset poll has already returned an
        // authoritative STATUS_TIMEOUT to the guest. It is not a successful
        // handoff and it is never permission to inject a signal, but repeated
        // polling is not proof that the waiter is parked forever. Keep the
        // observation as a caution and let the producer/Vd path explain why
        // the predicate never became true.
        if (evidence.timeout_class == .bounded_poll) {
            return decision(timed_out_class, .await_deadline, .caution, true);
        }
        const severe = evidence.timed_out_waits >= config.timeout_fault_threshold;
        return decision(
            timed_out_class,
            if (severe) .fault_before_resume else .await_authoritative_signal,
            if (severe) .fault else .caution,
            false,
        );
    }

    // No timing witness means the runtime knows that a wait-shaped operation
    // occurred, but not whether it parked or returned ready.  It must not be
    // promoted to a handoff just because a signal counter happens to match.
    if (evidence.successful_waits == 0) {
        if (evidence.waits != 0) {
            return decision(.insufficient_evidence, .observe_only, .caution, false);
        }
        return decision(.orphan_signal, .report_and_hold, .observation, true);
    }

    // A ready-on-entry result is already an authoritative completion.  It
    // must not be converted into a parked-consumer/orphan-wait finding merely
    // because no notifier was needed for that particular attempt.
    if (evidence.blocked_successes == 0 and
        evidence.ready_on_entry == evidence.successful_waits)
    {
        return decision(.ready_without_park, .continue_execution, .observation, true);
    }

    if (evidence.signals == 0) {
        if (evidence.notifier_state == .parked) {
            return decision(.notifier_parked, .report_and_hold, .caution, false);
        }
        return decision(.orphan_wait, .fault_before_resume, .fault, false);
    }

    const matched = @min(evidence.successful_waits, evidence.signals);
    if (matched < config.minimum_handshake_sample) {
        return decision(.insufficient_evidence, .observe_only, .caution, false);
    }

    return switch (evidence.progress) {
        .advanced => decision(.handshake_progressing, .continue_execution, .observation, true),
        .flat => decision(.handshake_stalled, .fault_before_resume, .fault, false),
        .unknown => decision(.insufficient_evidence, .observe_only, .caution, false),
    };
}

/// A bounded POSIX recovery request.  It is separate from `Evidence` because
/// a synthetic wake is an action request, not an inference about a guest wait.
pub const SpuriousWakeRequest = struct {
    object_kind: ObjectKind = .unknown,
    explicit_opt_in: bool = false,
    predicate_recheck_safe: bool = false,
    mutex_available: bool = false,
    waiter_parked: bool = false,
    generation_already_repaired: bool = false,
};

pub const SpuriousWakeDecision = struct {
    allowed: bool,
    reason: []const u8,
};

/// Permit only the narrow POSIX latitude used by the cooperative host
/// scheduler.  Every refusal is explicit so a future caller cannot mistake a
/// missing precondition for a harmless default.
pub fn spuriousWakeDecision(request: SpuriousWakeRequest) SpuriousWakeDecision {
    if (request.object_kind != .posix_condvar) {
        return .{ .allowed = false, .reason = "object_is_not_a_posix_condvar" };
    }
    if (!request.explicit_opt_in) {
        return .{ .allowed = false, .reason = "explicit_opt_in_missing" };
    }
    if (!request.predicate_recheck_safe) {
        return .{ .allowed = false, .reason = "predicate_recheck_not_proven_safe" };
    }
    if (!request.mutex_available) {
        return .{ .allowed = false, .reason = "associated_mutex_is_not_available" };
    }
    if (!request.waiter_parked) {
        return .{ .allowed = false, .reason = "waiter_is_not_parked" };
    }
    if (request.generation_already_repaired) {
        return .{ .allowed = false, .reason = "generation_already_repaired" };
    }
    return .{ .allowed = true, .reason = "posix_predicate_recheck_is_bounded" };
}

pub fn contractIsWellFormed() bool {
    if ((Config{}).minimum_handshake_sample != 8) return false;
    if ((Config{}).timeout_fault_threshold != 32) return false;
    if (bounded_poll_max_ms != 1000) return false;
    if (spuriousWakeDecision(.{
        .object_kind = .posix_condvar,
        .explicit_opt_in = true,
        .predicate_recheck_safe = true,
        .mutex_available = true,
        .waiter_parked = true,
    }).allowed != true) {
        return false;
    }
    if (spuriousWakeDecision(.{
        .object_kind = .guest_semaphore,
        .explicit_opt_in = true,
        .predicate_recheck_safe = true,
        .mutex_available = true,
        .waiter_parked = true,
    }).allowed) {
        return false;
    }
    return true;
}

test "timeouts are not parked orphan waits" {
    const result = decide(.{
        .object_kind = .guest_auto_reset_event,
        .waits = 4,
        .timed_out_waits = 4,
        .finite_deadline = true,
    }, .{});
    try std.testing.expectEqual(Classification.timeout_only, result.classification);
    try std.testing.expectEqual(Action.await_authoritative_signal, result.action);
    try std.testing.expectEqual(Severity.caution, result.severity);
    try std.testing.expect(!result.may_resume);
    try std.testing.expect(!result.may_synthesize_wake);
    try std.testing.expect(!result.requires_fault);
}

test "repeated timeout threshold becomes a strict fault" {
    const result = decide(.{
        .waits = 32,
        .timed_out_waits = 32,
        .finite_deadline = true,
    }, .{});
    try std.testing.expectEqual(Classification.timeout_only, result.classification);
    try std.testing.expectEqual(Action.fault_before_resume, result.action);
    try std.testing.expect(result.requires_fault);
}

test "a proven finite manual-reset poll does not become an indefinite-wait fault" {
    const timeout_class = classifyTimeout(.{
        .timeout_ms = 32,
        .timeout_known = true,
        .requested = true,
        .object_kind = .guest_manual_reset_event,
        .event_mode_known = true,
        .manual_reset = true,
    });
    try std.testing.expectEqual(TimeoutClass.bounded_poll, timeout_class);

    const result = decide(.{
        .object_kind = .guest_manual_reset_event,
        .timeout_class = timeout_class,
        .waits = 32,
        .timed_out_waits = 32,
    }, .{});
    try std.testing.expectEqual(Classification.timeout_only, result.classification);
    try std.testing.expectEqual(Action.await_deadline, result.action);
    try std.testing.expectEqual(Severity.caution, result.severity);
    try std.testing.expect(result.may_resume);
    try std.testing.expect(!result.may_synthesize_wake);
    try std.testing.expect(!result.requires_fault);
}

test "elapsed duration alone cannot prove a bounded poll" {
    try std.testing.expectEqual(
        TimeoutClass.finite_deadline,
        classifyTimeout(.{
            .timeout_ms = 32,
            .timeout_known = true,
            .requested = false,
            .object_kind = .guest_manual_reset_event,
            .event_mode_known = true,
            .manual_reset = true,
        }),
    );
}

test "ready-on-entry waits are not orphaned when no notifier was needed" {
    const result = decide(.{
        .object_kind = .guest_auto_reset_event,
        .waits = 3,
        .successful_waits = 3,
        .ready_on_entry = 3,
        .signals = 0,
        .progress = .advanced,
    }, .{});
    try std.testing.expectEqual(Classification.ready_without_park, result.classification);
    try std.testing.expectEqual(Action.continue_execution, result.action);
    try std.testing.expectEqual(Severity.observation, result.severity);
    try std.testing.expect(result.may_resume);
    try std.testing.expect(!result.may_synthesize_wake);
    try std.testing.expect(!result.requires_fault);
}

test "a matched flat handshake is never resumed" {
    const result = decide(.{
        .object_kind = .guest_semaphore,
        .waits = 14,
        .signals = 14,
        .successful_waits = 10,
        .blocked_successes = 10,
        .unknown_timing = 4,
        .progress = .flat,
        .same_site_reentries = 13,
    }, .{});
    try std.testing.expectEqual(Classification.handshake_stalled, result.classification);
    try std.testing.expectEqual(Action.fault_before_resume, result.action);
    try std.testing.expect(!result.may_resume);
    try std.testing.expect(!result.may_synthesize_wake);
}

test "a matched handshake with progress continues" {
    const result = decide(.{
        .waits = 8,
        .signals = 8,
        .successful_waits = 8,
        .blocked_successes = 8,
        .progress = .advanced,
    }, .{});
    try std.testing.expectEqual(Classification.handshake_progressing, result.classification);
    try std.testing.expectEqual(Action.continue_execution, result.action);
    try std.testing.expect(result.may_resume);
}

test "unknown progress remains evidence incomplete" {
    const result = decide(.{
        .waits = 8,
        .signals = 8,
        .successful_waits = 8,
        .progress = .unknown,
    }, .{});
    try std.testing.expectEqual(Classification.insufficient_evidence, result.classification);
    try std.testing.expect(!result.may_resume);
}

test "identity conflicts fault before a continuation can be selected" {
    const result = decide(.{
        .waits = 1,
        .signals = 1,
        .successful_waits = 1,
        .identity_conflict = true,
    }, .{});
    try std.testing.expectEqual(Classification.identity_conflict, result.classification);
    try std.testing.expectEqual(Action.fault_before_resume, result.action);
    try std.testing.expect(result.requires_fault);
}

test "only a bounded POSIX predicate recheck may synthesize a wake" {
    const allowed = spuriousWakeDecision(.{
        .object_kind = .posix_condvar,
        .explicit_opt_in = true,
        .predicate_recheck_safe = true,
        .mutex_available = true,
        .waiter_parked = true,
    });
    try std.testing.expect(allowed.allowed);

    const guest = spuriousWakeDecision(.{
        .object_kind = .guest_semaphore,
        .explicit_opt_in = true,
        .predicate_recheck_safe = true,
        .mutex_available = true,
        .waiter_parked = true,
    });
    try std.testing.expect(!guest.allowed);

    const unproven = spuriousWakeDecision(.{
        .object_kind = .posix_condvar,
        .explicit_opt_in = true,
        .predicate_recheck_safe = false,
        .mutex_available = true,
        .waiter_parked = true,
    });
    try std.testing.expect(!unproven.allowed);
}

test "all policy vocabulary is named and the package contract is valid" {
    inline for (@typeInfo(ObjectKind).@"enum".fields) |field| {
        const value: ObjectKind = @enumFromInt(field.value);
        try std.testing.expect(value.label().len != 0);
    }
    inline for (@typeInfo(Classification).@"enum".fields) |field| {
        const value: Classification = @enumFromInt(field.value);
        try std.testing.expect(value.label().len != 0);
        try std.testing.expect(value.guidance().len > 30);
    }
    inline for (@typeInfo(Action).@"enum".fields) |field| {
        const value: Action = @enumFromInt(field.value);
        try std.testing.expect(value.label().len != 0);
    }
    inline for (@typeInfo(ContinuationState).@"enum".fields) |field| {
        const value: ContinuationState = @enumFromInt(field.value);
        try std.testing.expect(value.label().len != 0);
        try std.testing.expect(value.guidance().len > 30);
    }
    inline for (@typeInfo(PcDomain).@"enum".fields) |field| {
        const value: PcDomain = @enumFromInt(field.value);
        try std.testing.expect(value.label().len != 0);
        try std.testing.expect(value.guidance().len > 20);
    }
    inline for (@typeInfo(PcQuality).@"enum".fields) |field| {
        const value: PcQuality = @enumFromInt(field.value);
        try std.testing.expect(value.label().len != 0);
    }
    try std.testing.expect((PcEvidence{
        .address = 0x8258_2a98,
        .domain = .xenia_guest_ppc,
        .quality = .tracked,
    }).provesGuestControlFlow());
    try std.testing.expect(!(PcEvidence{
        .address = 0x1be_680,
        .domain = .rosette_translated_x86,
        .quality = .direct,
    }).provesGuestControlFlow());
    try std.testing.expect(ContinuationState.transitioned.provesControlFlowTransition());
    try std.testing.expect(!ContinuationState.same_site.provesControlFlowTransition());
    try std.testing.expect(contractIsWellFormed());
}
