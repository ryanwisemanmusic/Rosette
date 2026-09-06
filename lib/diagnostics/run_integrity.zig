//! Judging the run against the standards it has to meet, and stopping at the
//! first one it fails.
//!
//! The contract in `rosette_run_integrity_contract` decides; this keeps the
//! history. History matters here in a way it does not for a plain assertion:
//! an invariant that was satisfied for six billion steps and then failed is a
//! regression with a step number attached, and an invariant that has never
//! armed is a hole in the observation rather than a passing grade.
//!
//! The defect this was written against is not one line in a log. It is that a
//! run could accumulate a never-notified park, a wait that only times out, an
//! output handoff that was never connected, a translation cache evicting live
//! work at 85%, six emulator assertions and a frame the window showed that
//! nothing took custody of — and still run for two thousand seconds, producing
//! a log in which every one of those is a line among tens of thousands.

const std = @import("std");
const contract = @import("rosette_run_integrity_contract");

pub const Invariant = contract.Invariant;
pub const Owner = contract.Owner;
pub const Class = contract.Class;
pub const State = contract.State;
pub const LivenessScope = contract.LivenessScope;
pub const Observation = contract.Observation;
pub const Judgement = contract.Judgement;
pub const Policy = contract.Policy;
pub const invariant_count = contract.invariant_count;
pub const schema_version = contract.schema_version;
pub const capabilityProgressWitnessStep = contract.capabilityProgressWitnessStep;
pub const capabilityProgressQuietSteps = contract.capabilityProgressQuietSteps;
pub const budget_observation_host_seconds = contract.budget_observation_host_seconds;
pub const vd_swap_probe_floor = contract.vd_swap_probe_floor;

/// Select the strict liveness scope from independent runtime evidence.
///
/// The scope is intentionally derived here rather than inferred by the
/// package from a counter. A host wait can exist during loader/translator
/// startup without being a failed application handshake. Guest execution is
/// the first boundary that makes application-side waits relevant; a proven GPU
/// event is stronger evidence and wins if both are present.
pub fn livenessScope(guest_main_ready: bool, gpu_activity: bool) LivenessScope {
    if (gpu_activity) return .gpu_activity;
    if (guest_main_ready) return .guest_execution;
    return .pre_guest_startup;
}

/// A state transition is retained separately from the current state so a
/// report can say whether a violation just appeared, regressed, or merely
/// changed its measured detail. This is the event boundary used by the
/// runtime trace; it prevents a persistent fault from printing the same large
/// evidence block at every heartbeat while still recording every meaningful
/// change.
pub const Transition = enum(u8) {
    unchanged,
    armed,
    entered_violation,
    regression,
    recovered,
    unarmed,
    changed,

    pub fn label(self: Transition) []const u8 {
        return switch (self) {
            .unchanged => "unchanged",
            .armed => "armed",
            .entered_violation => "entered-violation",
            .regression => "regression",
            .recovered => "recovered",
            .unarmed => "became-unarmed",
            .changed => "changed",
        };
    }

    pub fn tracesViolation(self: Transition) bool {
        return self == .entered_violation or self == .regression or self == .changed;
    }
};

pub const Record = struct {
    state: State = .not_armed,
    detail: u64 = 0,
    /// Step at which this invariant first became judgeable. Zero while unarmed.
    armed_step: u64 = 0,
    /// Step at which it first failed, and the value it failed with. Retained
    /// separately from `detail` so a violation that later clears still says
    /// when it happened.
    first_violation_step: u64 = 0,
    first_violation_detail: u64 = 0,
    violations: u64 = 0,
    observations: u64 = 0,
    /// True once this invariant has been satisfied at least once. An invariant
    /// that armed straight into a violation and one that regressed after
    /// holding are different findings.
    ever_satisfied: bool = false,
    /// Explicitly stepped past by the reader.
    allowed: bool = false,
    /// The complete input snapshot at the first checkpoint at which this
    /// invariant became judgeable. Keeping it here makes a later report
    /// independent of whatever the live ledgers have become.
    first_armed_observation: Observation = .{},
    has_armed_observation: bool = false,
    /// The complete input snapshot at the first violation. This is the
    /// difference between "the current counter is 1" and "this became 1 after
    /// the capability quiet window closed with these exact prerequisites".
    first_violation_observation: Observation = .{},
    has_first_violation_observation: bool = false,
    /// Transition observed by the most recent evaluation. The process logger
    /// uses it as a bounded event trigger for detailed violation evidence.
    last_transition: Transition = .unchanged,

    pub fn armed(self: Record) bool {
        return self.state != .not_armed or self.armed_step != 0;
    }

    pub fn regressed(self: Record) bool {
        return self.state == .violated and self.ever_satisfied;
    }

    /// Whether the configured allow-list actually applies to this invariant.
    /// Some findings are diagnostic and can be stepped past; GPU
    /// pre-initialization ordering and controller authority firewalls are
    /// deliberately not bypassable.
    pub fn allowlistApplies(self: Record, invariant: Invariant) bool {
        return self.allowed and !invariant.nonBypassable();
    }
};

fn transitionFor(previous: State, previous_detail: u64, current: State, current_detail: u64) Transition {
    if (previous == current and previous_detail == current_detail) return .unchanged;
    if (current == .violated) {
        return if (previous == .violated)
            .changed
        else if (previous == .satisfied)
            .regression
        else
            .entered_violation;
    }
    if (previous == .violated and current == .satisfied) return .recovered;
    if (previous == .not_armed and current != .not_armed) return .armed;
    if (previous != .not_armed and current == .not_armed) return .unarmed;
    return .changed;
}

pub const Summary = struct {
    armed: usize = 0,
    satisfied: usize = 0,
    violated: usize = 0,
    unarmed: usize = 0,
    allowed: usize = 0,
    regressions: usize = 0,
    /// The invariant the run should stop at, if any survives the allow list.
    stop_at: ?Invariant = null,

    pub fn clean(self: Summary) bool {
        return self.violated == 0;
    }

    pub fn verdict(self: Summary) []const u8 {
        if (self.violated != 0 and self.stop_at == null)
            return "every violation this checkpoint was explicitly stepped past by ROSETTE_RUN_INTEGRITY_ALLOW; the run continues on a reader's decision, not because it is clean";
        if (self.regressions != 0)
            return "an invariant that was holding has started failing; a regression has a step number attached and is the most specific finding in this report";
        if (self.violated != 0)
            return "the run is not meeting a standard it has to meet; the stop line below names the invariant, its owner and what to do about it";
        if (self.armed == 0)
            return "no invariant has become judgeable yet; the run has not reached the point where any of these can be assessed and this report says nothing";
        if (self.unarmed != 0)
            return "every invariant that has become judgeable is holding; the unarmed ones below are unobserved rather than passing, and each names what would arm it";
        return "every invariant is armed and holding";
    }
};

pub const Ledger = struct {
    policy: Policy = .fault,
    records: [invariant_count]Record = [_]Record{.{}} ** invariant_count,
    evaluations: u64 = 0,
    /// Latched so a caller that keeps running cannot report two first stops.
    stopped: bool = false,
    stop_invariant: Invariant = .window_forwarding_accounted,
    stop_step: u64 = 0,
    stop_detail: u64 = 0,
    last_observation: Observation = .{},

    pub fn configure(self: *Ledger, policy: Policy, allow_list: []const u8) void {
        self.policy = policy;
        var index: u8 = 0;
        while (index < invariant_count) : (index += 1) {
            const invariant: Invariant = @enumFromInt(index);
            self.records[index].allowed = contract.allowedByList(allow_list, invariant);
        }
    }

    pub fn record(self: *const Ledger, invariant: Invariant) Record {
        return self.records[@intFromEnum(invariant)];
    }

    /// Judge every invariant against one observation and return what to do.
    pub fn evaluate(self: *Ledger, observation: Observation) Summary {
        self.evaluations +|= 1;
        self.last_observation = observation;
        var judgements = [_]Judgement{.{}} ** invariant_count;
        var summary = Summary{};

        var index: u8 = 0;
        while (index < invariant_count) : (index += 1) {
            const invariant: Invariant = @enumFromInt(index);
            const judgement = contract.judge(invariant, observation);
            const entry = &self.records[index];
            const previous_state = entry.state;
            const previous_detail = entry.detail;
            entry.observations +|= 1;
            entry.last_transition = transitionFor(
                previous_state,
                previous_detail,
                judgement.state,
                judgement.detail,
            );
            if (judgement.state != .not_armed and !entry.has_armed_observation) {
                entry.first_armed_observation = observation;
                entry.has_armed_observation = true;
            }
            entry.state = judgement.state;
            entry.detail = judgement.detail;
            if (judgement.state != .not_armed and entry.armed_step == 0)
                entry.armed_step = @max(observation.step, 1);
            switch (judgement.state) {
                .not_armed => summary.unarmed += 1,
                .satisfied => {
                    summary.armed += 1;
                    summary.satisfied += 1;
                    entry.ever_satisfied = true;
                },
                .violated => {
                    summary.armed += 1;
                    summary.violated += 1;
                    entry.violations +|= 1;
                    if (!entry.has_first_violation_observation) {
                        entry.first_violation_observation = observation;
                        entry.has_first_violation_observation = true;
                    }
                    if (entry.first_violation_step == 0) {
                        entry.first_violation_step = @max(observation.step, 1);
                        entry.first_violation_detail = judgement.detail;
                    }
                    if (entry.ever_satisfied) summary.regressions += 1;
                    if (entry.allowlistApplies(invariant)) {
                        summary.allowed += 1;
                    } else {
                        // Only a violation that is not stepped past is a
                        // candidate to stop at. Non-bypassable invariants stay
                        // in this set even when their label was supplied in the
                        // allow list.
                        judgements[index] = judgement;
                    }
                },
            }
        }

        summary.stop_at = contract.firstToStopAt(judgements);
        if (summary.stop_at) |invariant| {
            if ((self.policy == .fault or invariant.nonBypassable()) and !self.stopped) {
                self.stopped = true;
                self.stop_invariant = invariant;
                self.stop_step = observation.step;
                self.stop_detail = self.records[@intFromEnum(invariant)].detail;
            }
        }
        return summary;
    }

    /// Whether the run should terminate now. Separate from `evaluate` so the
    /// caller can write the whole report before acting on it.
    pub fn shouldStop(self: *const Ledger, summary: Summary) bool {
        const invariant = summary.stop_at orelse return false;
        return self.policy == .fault or invariant.nonBypassable();
    }

    pub fn fingerprint(self: *const Ledger) u64 {
        var hash: u64 = 0x243F_6A88_85A3_08D3;
        for (self.records) |entry| {
            hash = mix(hash, @intFromEnum(entry.state));
            hash = mix(hash, entry.detail);
            hash = mix(hash, entry.violations);
        }
        return hash;
    }
};

/// Name the predicate family that caused an invariant to fail. This deliberately
/// describes the observed condition rather than restating `remedy()`: the
/// latter tells an operator what to change, while this tells a trace reader
/// which input in the snapshot was decisive.
pub fn traceCause(invariant: Invariant, observation: Observation) []const u8 {
    return switch (invariant) {
        .window_forwarding_accounted => if (observation.window_unaccountable != 0)
            "window admission recorded unaccountable forwarding"
        else
            "window forwarding account is not complete",
        .presented_frames_in_custody => "window presentations exceed frames in custody",
        .swap_boundary_offered => "the emulator reached more swap boundaries than the window offered",
        .guest_output_handoff_connected => "presenter was ready and a genuine guest output opportunity was observed, but no producer published a frame",
        .no_never_notified_park => "a never-notified park exceeded the liveness threshold without progress",
        .no_stalled_wait_handshake => if (observation.wait_graph_cycles != 0)
            "a mature wait graph contains a reciprocal cycle"
        else if (observation.wait_graph_dropped_objects != 0)
            "wait graph identities were dropped, so absence of a cycle cannot be trusted"
        else
            "a mature wait/signal handshake is cycling without independent progress",
        .wait_receives_signals => "a wait subject timed out repeatedly without receiving a signal",
        .no_unsatisfied_capability => "an exercised capability remains unsatisfied after the progress quiet window",
        .no_harness_substitution => "Rosette substitution produced application-visible work",
        .translation_cache_converges => if (observation.translation_conflict_fills != 0)
            "translation fills are dominated by set conflicts"
        else if (observation.translation_cold_evictions != 0)
            "translation fills are dominated by cold evictions"
        else if (observation.translation_stale_refills != 0)
            "translation fills include stale source-byte refills"
        else if (observation.translation_flush_refills != 0)
            "translation fills include coarse invalidation refills"
        else
            "translation cache pressure has not converged",
        .no_recorded_anomaly => if (observation.recorded_anomalies != 0)
            "the anomaly ledger contains one or more recorded anomalies"
        else
            "the pause-causality ledger contains a refuted, missing, or dropped pause transaction",
        .every_waiter_has_a_notifier => "a waiter has no observed notifier on its wait subject",
        .every_park_has_a_reason => "a parked thread has no reason in the scheduler model",
        .single_master_owner => "an event has an ownership pair the master-owner contract rejects",
        .every_boundary_substantiated => if (observation.diverged_boundaries != 0)
            "application and Rosette answered a boundary differently"
        else if (observation.measurement_drift_boundaries != 0)
            "two boundary answers use incompatible measurement domains"
        else
            "Rosette has an answerable boundary with no recorded account",
        .no_reinterpreting_texture_format => "a guest texture format is being served through an unproven reinterpretation",
        .all_critical_capabilities_proven => "critical capability accounting still contains degraded, failed, or untested entries",
        .no_degraded_critical_capability => "a critical capability answers calls without proving that it performs its job",
        .no_unverified_pm4_input => if (observation.pm4_out_of_range_register_writes != 0)
            "live PM4 wrote outside the Xenos register file"
        else if (observation.pm4_unclassified_register_writes != 0)
            "live PM4 wrote registers outside Rosette's classified Xenos map"
        else if (observation.pm4_packet_errors != 0 or observation.pm4_invalid_packets != 0)
            "live PM4 execution rejected a packet"
        else if (observation.pm4_truncated_rings != 0)
            "live PM4 input ended before its declared packet span"
        else if (observation.pm4_unknown_opcodes != 0)
            "live PM4 contained an opcode Rosette does not implement"
        else
            "live PM4 indirect traversal was not proven complete",
        .no_mandatory_order_violation => "the mandatory-order ledger observed a mandatory dependency after its dependant",
        .no_gpu_preinitialization_order_inversion => "GPU pre-initialization established a dependent element before its prerequisite",
        .no_undercounting_observer => "an observer that sees every occurrence is below another observer's count of the same fact",
        .bounded_poll_receives_signals => "a bounded manual-reset poll has never been signalled while the producer beside it stayed silent",
        .no_presenter_failure => "the native presenter entered a non-retryable failure state",
        .no_actionable_provisioning_refusal => "console-owned provisioning custody has an actionable unresolved failure",
        .no_actionable_wait_policy_fault => "the wait-handshake policy classified an observed object as a fault",
        .no_invalid_application_controller_decision => "the application controller emitted an internally inconsistent or unauthorized decision",
        .no_unclassified_execution_profile => "a readable decisive execution profile still has unclassified or unresolved samples",
        .no_unprobed_reachable_stage => "a swap stage with met prerequisites has never had one probe attempted while probes beside it have run",
        .no_rosette_closable_starvation => "a reachable swap stage was probed and read nothing for a cause Rosette owns: an unwired probe or a counter nothing feeds",
        .no_run_budget_deficit => "the settled run is below its declared guest-time throughput budget",
        .no_proven_deadlock => "the deadlock predictor proved a mature wait-for deadlock",
        .no_unproven_essential_component => "an essential component was used without a readiness proof or its proof reported failure",
        .all_required_witnesses_corroborated => "the required monotone witness set reached closure with one or more subjects lacking an agreeing independent observer",
        .no_contested_claim => "two live observers of one claim disagree about the present and the contradicted source is still repeating its value",
        .no_settled_unknown_mapping => "a classifier repeatedly declined a raw value a conclusion needed; the answer is a missing table entry, not more runtime",
        .frontier_boundary_corroborated => "the frontier blames a boundary that was reached on none of its armed addresses and that nothing else has spoken about",
    };
}

/// State the admission condition that made the judgement actionable. This is
/// kept as a stable label so tooling can group failures across runs while the
/// human-readable predicate snapshot carries the actual values.
pub fn traceGate(invariant: Invariant) []const u8 {
    return switch (invariant) {
        .window_forwarding_accounted => "window_forwardings > 0",
        .presented_frames_in_custody => "frames_presented_to_window > 0",
        .swap_boundary_offered => "swap_boundaries_reached > 0",
        .guest_output_handoff_connected => "presenter_ready && guest_output_opportunity_observed && granular_output_evidence && producer_quiet_steps >= threshold",
        .no_never_notified_park => "liveness_scope != pre_guest_startup && never_notified_park_steps >= threshold",
        .no_stalled_wait_handshake => "liveness_scope != pre_guest_startup && wait_graph_events > 0 && a mature wait-graph finding exists",
        .wait_receives_signals => "liveness_scope != pre_guest_startup && unsignalled_wait_timeouts >= threshold",
        .no_unsatisfied_capability => "capabilities_exercised > 0 && capability_progress_quiet_steps >= threshold",
        .no_harness_substitution => "harness_substitutions > 0",
        .translation_cache_converges => "translation cache is populated and the pressure window is actionable",
        .no_recorded_anomaly => "recorded_anomalies + pause_transaction_defects > 0",
        .every_waiter_has_a_notifier => "liveness_scope != pre_guest_startup && waiters_without_a_notifier > 0",
        .every_park_has_a_reason => "parks_without_a_reason > 0",
        .single_master_owner => "ownership_violations > 0",
        .every_boundary_substantiated => "substantiation_armed && an answerable boundary is unresolved",
        .no_reinterpreting_texture_format => "texture_formats_probed && reinterpreted_texture_formats > 0",
        .all_critical_capabilities_proven => "capability_progress_quiet_steps >= threshold && critical_capabilities_total > 0",
        .no_degraded_critical_capability => "capability_progress_quiet_steps >= threshold && critical_capabilities_total > 0",
        .no_unverified_pm4_input => "live PM4 packets observed and pm4_defects == 0",
        .no_mandatory_order_violation => "mandatory_order_armed && mandatory_order_mandatory_violations == 0",
        .no_gpu_preinitialization_order_inversion => "gpu_preinitialization_inversions + gpu_preinitialization_inversions_dropped == 0",
        .no_undercounting_observer => "monotone_witness_corroboration_possible && settled_observer_undercounts == 0",
        .bounded_poll_receives_signals => "liveness_scope != pre_guest_startup && bounded_timeout_attempts >= threshold && bounded_timeout_signals == 0 && producer_quiet_steps >= threshold",
        .no_presenter_failure => "presenter_attempted && presenter_nonretryable_failures == 0",
        .no_actionable_provisioning_refusal => "provisioning_armed && custody failure/refusal count == 0",
        .no_actionable_wait_policy_fault => "wait_policy_observed && wait_policy_faults == 0",
        .no_invalid_application_controller_decision => "application_controller_decisions > 0 && application_controller_contract_violations == 0",
        .no_unclassified_execution_profile => "execution_profile_readable && execution_profile_decisive && unclassified + unresolved == 0",
        .no_unprobed_reachable_stage => "vd_swap_probe_attempt_floor >= threshold && vd_swap_unprobed_reachable_stages == 0",
        .no_rosette_closable_starvation => "vd_swap_probe_attempt_floor >= threshold && vd_swap_rosette_closable_starvations == 0",
        .no_run_budget_deficit => "run_budget_observed && run_budget_deficit == false",
        .no_proven_deadlock => "liveness_scope != pre_guest_startup && deadlock_observed && deadlock_proven == true",
        .no_unproven_essential_component => "component_readiness_armed && essential_component_gaps > 0",
        .all_required_witnesses_corroborated => "monotone_witness_closure_ready && monotone_witness_agreement_debt == 0",
        .no_contested_claim => "claim_reconciliation_multi_source > 0 && claim_reconciliation_contested == 0",
        .no_settled_unknown_mapping => "settled_unknown_mappings == 0",
        .frontier_boundary_corroborated => "frontier_armed && crossed_elsewhere > 0 && settled >= threshold && !external_progress_fresh && (addresses_reached > 0 || corroborating_observers > 0)",
    };
}

/// Parse `ROSETTE_RUN_INTEGRITY`. Anything unrecognised keeps the default, so a
/// typo cannot silently disarm the gate.
pub fn policyFromText(value: ?[]const u8, default: Policy) Policy {
    const text = value orelse return default;
    if (std.mem.eql(u8, text, "fault")) return .fault;
    if (std.mem.eql(u8, text, "warn")) return .warn;
    if (std.mem.eql(u8, text, "observe")) return .observe;
    return default;
}

fn mix(hash: u64, value: u64) u64 {
    var next = hash ^ (value +% 0x9E37_79B9_7F4A_7C15 +% (hash << 6) +% (hash >> 2));
    next ^= next >> 33;
    next = next *% 0xFF51_AFD7_ED55_8CCD;
    next ^= next >> 29;
    return next;
}

// ---------------------------------------------------------------------------

fn healthyObservation() Observation {
    return .{
        .step = 1_000_000,
        .window_forwardings = 6,
        .window_unaccountable = 0,
        .frames_presented_to_window = 10,
        .frames_in_custody = 10,
        .swap_boundaries_reached = 2,
        .swap_boundaries_offered = 2,
        .presenter_ready = true,
        .draws_consumed = 24,
        .frames_published_by_any_producer = 4,
        .producer_quiet_steps = 10,
        .capabilities_exercised = 23,
        .capabilities_unsatisfied = 0,
        .critical_capabilities_total = 11,
        .critical_capabilities_satisfied = 11,
        .critical_capabilities_degraded = 0,
        .critical_capabilities_unsatisfied = 0,
        .critical_capabilities_untested = 0,
        .translation_cache_entries = 262_144,
        .translation_vacant_fills = 262_144,
        .translation_conflict_fills = 1000,
        .translation_hits = 1_000_000,
        .translation_misses = 1000,
        .capability_progress_quiet_steps = 2_000_000_000,
    };
}

test "a healthy checkpoint stops nothing" {
    var ledger = Ledger{};
    const summary = ledger.evaluate(healthyObservation());
    try std.testing.expect(summary.clean());
    try std.testing.expect(summary.stop_at == null);
    try std.testing.expect(!ledger.shouldStop(summary));
    try std.testing.expect(!ledger.stopped);
}

test "a violation stops the run and latches what it stopped at" {
    var ledger = Ledger{};
    var observation = healthyObservation();
    observation.frames_in_custody = 0;
    const summary = ledger.evaluate(observation);
    try std.testing.expectEqual(Invariant.presented_frames_in_custody, summary.stop_at.?);
    try std.testing.expect(ledger.shouldStop(summary));
    try std.testing.expectEqual(Invariant.presented_frames_in_custody, ledger.stop_invariant);
    try std.testing.expectEqual(@as(u64, 1_000_000), ledger.stop_step);
    try std.testing.expectEqual(@as(u64, 10), ledger.stop_detail);
}

test "the first stop is latched and a later one does not replace it" {
    var ledger = Ledger{};
    var observation = healthyObservation();
    observation.frames_in_custody = 0;
    _ = ledger.evaluate(observation);
    observation.step = 2_000_000;
    observation.frames_in_custody = 10;
    observation.recorded_anomalies = 4;
    _ = ledger.evaluate(observation);
    try std.testing.expectEqual(Invariant.presented_frames_in_custody, ledger.stop_invariant);
    try std.testing.expectEqual(@as(u64, 1_000_000), ledger.stop_step);
}

test "an unarmed invariant is reported apart from a satisfied one" {
    var ledger = Ledger{};
    // Nothing has happened: every invariant that needs evidence is unarmed.
    const summary = ledger.evaluate(.{});
    try std.testing.expect(summary.clean());
    try std.testing.expect(summary.unarmed != 0);
    try std.testing.expect(std.mem.indexOf(u8, summary.verdict(), "unobserved rather than passing") != null or
        std.mem.indexOf(u8, summary.verdict(), "no invariant has become judgeable") != null);
    try std.testing.expect(!ledger.record(.presented_frames_in_custody).armed());
}

test "arming is remembered even after the invariant stops being judgeable" {
    var ledger = Ledger{};
    var observation = healthyObservation();
    _ = ledger.evaluate(observation);
    try std.testing.expect(ledger.record(.presented_frames_in_custody).armed());
    observation.frames_presented_to_window = 0;
    _ = ledger.evaluate(observation);
    try std.testing.expectEqual(State.not_armed, ledger.record(.presented_frames_in_custody).state);
    // Still counted as having armed, so a disappearing observation reads as an
    // observer that stopped rather than as a fact that was never true.
    try std.testing.expect(ledger.record(.presented_frames_in_custody).armed());
}

test "a regression is distinguished from a violation that was always there" {
    var ledger = Ledger{};
    var observation = healthyObservation();
    _ = ledger.evaluate(observation);
    observation.step = 2_000_000;
    observation.frames_in_custody = 0;
    const summary = ledger.evaluate(observation);
    try std.testing.expectEqual(@as(usize, 1), summary.regressions);
    try std.testing.expect(ledger.record(.presented_frames_in_custody).regressed());
    try std.testing.expectEqual(@as(u64, 2_000_000), ledger.record(.presented_frames_in_custody).first_violation_step);
    try std.testing.expect(std.mem.indexOf(u8, summary.verdict(), "regression") != null);
}

test "violation history retains predicate snapshots and meaningful transitions" {
    var ledger = Ledger{};
    var observation = healthyObservation();

    _ = ledger.evaluate(observation);
    const armed = ledger.record(.presented_frames_in_custody);
    try std.testing.expectEqual(Transition.armed, armed.last_transition);
    try std.testing.expect(armed.has_armed_observation);
    try std.testing.expectEqual(@as(u64, 1_000_000), armed.first_armed_observation.step);
    try std.testing.expectEqual(@as(u64, 10), armed.first_armed_observation.frames_in_custody);

    observation.step = 2_000_000;
    observation.frames_in_custody = 0;
    _ = ledger.evaluate(observation);
    const regressed = ledger.record(.presented_frames_in_custody);
    try std.testing.expectEqual(Transition.regression, regressed.last_transition);
    try std.testing.expect(regressed.has_first_violation_observation);
    try std.testing.expectEqual(@as(u64, 2_000_000), regressed.first_violation_observation.step);
    try std.testing.expectEqual(@as(u64, 0), regressed.first_violation_observation.frames_in_custody);
    try std.testing.expectEqual(@as(u64, 10), regressed.first_violation_detail);
    try std.testing.expectEqualStrings(
        "window presentations exceed frames in custody",
        traceCause(.presented_frames_in_custody, regressed.first_violation_observation),
    );

    // The violation counter continues to account for every checkpoint, but a
    // repeated identical judgement is not a new trace event.
    _ = ledger.evaluate(observation);
    const repeated = ledger.record(.presented_frames_in_custody);
    try std.testing.expectEqual(Transition.unchanged, repeated.last_transition);
    try std.testing.expectEqual(@as(u64, 2), repeated.violations);
    try std.testing.expectEqual(@as(u64, 2_000_000), repeated.first_violation_observation.step);

    observation.step = 3_000_000;
    observation.frames_in_custody = observation.frames_presented_to_window;
    _ = ledger.evaluate(observation);
    try std.testing.expectEqual(
        Transition.recovered,
        ledger.record(.presented_frames_in_custody).last_transition,
    );
}

test "every invariant exposes stable trace metadata" {
    inline for (@typeInfo(Invariant).@"enum".fields) |field| {
        const invariant: Invariant = @enumFromInt(field.value);
        try std.testing.expect(traceCause(invariant, .{}).len != 0);
        try std.testing.expect(traceGate(invariant).len != 0);
    }
    try std.testing.expect(Transition.entered_violation.tracesViolation());
    try std.testing.expect(Transition.regression.tracesViolation());
    try std.testing.expect(Transition.changed.tracesViolation());
    try std.testing.expect(!Transition.unchanged.tracesViolation());
    try std.testing.expect(!Transition.recovered.tracesViolation());
}

test "an allowed invariant is still judged and recorded, only not stopped at" {
    var ledger = Ledger{};
    ledger.configure(.fault, "presented-frames-in-custody");
    var observation = healthyObservation();
    observation.frames_in_custody = 0;
    const summary = ledger.evaluate(observation);
    try std.testing.expectEqual(@as(usize, 1), summary.violated);
    try std.testing.expectEqual(@as(usize, 1), summary.allowed);
    try std.testing.expect(summary.stop_at == null);
    try std.testing.expect(!ledger.shouldStop(summary));
    try std.testing.expect(!summary.clean());
    try std.testing.expect(std.mem.indexOf(u8, summary.verdict(), "stepped past") != null);
    // The counter is exact whether or not it was stepped past.
    try std.testing.expectEqual(@as(u64, 1), ledger.record(.presented_frames_in_custody).violations);
}

test "stepping past one violation reaches the next" {
    var ledger = Ledger{};
    ledger.configure(.fault, "presented-frames-in-custody");
    var observation = healthyObservation();
    observation.frames_in_custody = 0;
    observation.recorded_anomalies = 6;
    const summary = ledger.evaluate(observation);
    try std.testing.expectEqual(Invariant.no_recorded_anomaly, summary.stop_at.?);
}

test "observe and warn record everything and stop nothing" {
    for ([_]Policy{ .observe, .warn }) |policy| {
        var ledger = Ledger{};
        ledger.configure(policy, "");
        var observation = healthyObservation();
        observation.frames_in_custody = 0;
        const summary = ledger.evaluate(observation);
        try std.testing.expectEqual(@as(usize, 1), summary.violated);
        try std.testing.expect(summary.stop_at != null);
        try std.testing.expect(!ledger.shouldStop(summary));
        try std.testing.expect(!ledger.stopped);
    }
}

test "GPU preinitialization inversion cannot be allowlisted or disarmed" {
    for ([_]Policy{ .observe, .warn, .fault }) |policy| {
        var ledger = Ledger{};
        ledger.configure(policy, "no-gpu-preinitialization-order-inversion");
        var observation = healthyObservation();
        observation.gpu_preinitialization_inversions = 1;
        const summary = ledger.evaluate(observation);

        try std.testing.expectEqual(@as(usize, 1), summary.violated);
        try std.testing.expectEqual(@as(usize, 0), summary.allowed);
        try std.testing.expectEqual(
            Invariant.no_gpu_preinitialization_order_inversion,
            summary.stop_at.?,
        );
        try std.testing.expect(ledger.shouldStop(summary));
        try std.testing.expect(ledger.stopped);
        try std.testing.expect(!ledger.record(.no_gpu_preinitialization_order_inversion).allowlistApplies(
            .no_gpu_preinitialization_order_inversion,
        ));
    }
}

test "policy parsing keeps the default on anything unrecognised" {
    try std.testing.expectEqual(Policy.fault, policyFromText("fault", .warn));
    try std.testing.expectEqual(Policy.observe, policyFromText("observe", .fault));
    try std.testing.expectEqual(Policy.warn, policyFromText("warn", .fault));
    try std.testing.expectEqual(Policy.fault, policyFromText("Fault", .fault));
    try std.testing.expectEqual(Policy.fault, policyFromText(null, .fault));
}

test "liveness scope does not arm before guest execution" {
    try std.testing.expectEqual(
        LivenessScope.pre_guest_startup,
        livenessScope(false, false),
    );
    try std.testing.expectEqual(
        LivenessScope.guest_execution,
        livenessScope(true, false),
    );
    // GPU evidence is the stronger boundary even when the guest breadcrumb
    // arrived through a path the pipeline observer did not recognize.
    try std.testing.expectEqual(
        LivenessScope.gpu_activity,
        livenessScope(false, true),
    );
}

test "the fingerprint moves only when a judgement changes" {
    var ledger = Ledger{};
    const observation = healthyObservation();
    _ = ledger.evaluate(observation);
    const first = ledger.fingerprint();
    _ = ledger.evaluate(observation);
    try std.testing.expectEqual(first, ledger.fingerprint());
    var changed = observation;
    changed.recorded_anomalies = 1;
    _ = ledger.evaluate(changed);
    try std.testing.expect(ledger.fingerprint() != first);
}

// The whole point, stated as a test: the 2026-08-27 run must not have been
// allowed to reach step 6.8 billion. Its raw PM4 draw count is deliberately
// not treated as guest-output evidence: that run did not prove a target-backed
// draw, resolve, swap boundary, or VdSwap packet.
test "the observed run is stopped rather than allowing raw draws to arm output" {
    var ledger = Ledger{};
    const summary = ledger.evaluate(.{
        .step = 6_800_000_000,
        .liveness_scope = .gpu_activity,
        .window_forwardings = 6,
        .frames_presented_to_window = 62,
        .frames_in_custody = 61,
        .presenter_ready = true,
        .draws_consumed = 24,
        .frames_published_by_any_producer = 0,
        .producer_quiet_steps = 3_549_168_487,
        .longest_never_notified_park_steps = 6_734_887_829,
        .unsignalled_wait_timeouts = 90,
        .capabilities_exercised = 23,
        .capabilities_unsatisfied = 2,
        .translation_cache_entries = 262_144,
        .translation_vacant_fills = 262_144,
        .translation_conflict_fills = 1_610_194,
        .translation_hits = 6_805_578_866,
        .translation_misses = 1_872_338,
        .capability_progress_quiet_steps = 1_800_000_000,
        .recorded_anomalies = 6,
    });
    try std.testing.expect(!summary.clean());
    // Raw host-worker wait silence is retained as diagnosis, but it is not a
    // fatal liveness violation until guest/registry/frozen-run evidence proves
    // that the parked worker had an actionable notifier obligation.
    try std.testing.expectEqual(@as(usize, 4), summary.violated);
    try std.testing.expect(ledger.shouldStop(summary));
    try std.testing.expectEqual(Owner.rosette_harness, summary.stop_at.?.owner());
    try std.testing.expectEqual(
        State.not_armed,
        ledger.record(.guest_output_handoff_connected).state,
    );
}
