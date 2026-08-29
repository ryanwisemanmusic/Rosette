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

    pub fn armed(self: Record) bool {
        return self.state != .not_armed or self.armed_step != 0;
    }

    pub fn regressed(self: Record) bool {
        return self.state == .violated and self.ever_satisfied;
    }
};

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
            entry.observations +|= 1;
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
                    if (entry.first_violation_step == 0) {
                        entry.first_violation_step = @max(observation.step, 1);
                        entry.first_violation_detail = judgement.detail;
                    }
                    if (entry.ever_satisfied) summary.regressions += 1;
                    if (entry.allowed) {
                        summary.allowed += 1;
                    } else {
                        // Only an unallowed violation is a candidate to stop at.
                        judgements[index] = judgement;
                    }
                },
            }
        }

        summary.stop_at = contract.firstToStopAt(judgements);
        if (summary.stop_at) |invariant| {
            if (self.policy == .fault and !self.stopped) {
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
        return self.policy == .fault and summary.stop_at != null;
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
// allowed to reach step 6.8 billion.
test "the observed run is stopped rather than allowed to continue" {
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
    try std.testing.expectEqual(@as(usize, 6), summary.violated);
    try std.testing.expect(ledger.shouldStop(summary));
    try std.testing.expectEqual(Owner.rosette_harness, summary.stop_at.?.owner());
}
