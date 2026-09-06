//! Which of several counters of the same increasing fact a report may quote.
//!
//! The contract in `rosette_monotone_witness_contract` decides; this keeps the
//! readings. Keeping them matters as much as the decision: the finding a
//! reader needs is rarely "these two numbers differ" but "this ledger stopped
//! listening four and a half billion steps before the other one, and every
//! verdict printed since is about the silence of its carrier".
//!
//! Nothing here reaches into another ledger. Observers state their own
//! numbers; the floor is published back and the consumers that want it adopt
//! it explicitly. A reconciler that wrote into the ledgers it reconciles would
//! be a second author of every fact it touches, and two authors is the defect
//! this file exists to catch.

const std = @import("std");
const contract = @import("rosette_monotone_witness_contract");

pub const Subject = contract.Subject;
pub const Witness = contract.Witness;
pub const Finding = contract.Finding;
pub const Reading = contract.Reading;
pub const Reconciliation = contract.Reconciliation;
pub const subject_count = contract.subject_count;
pub const required_subject_count = contract.required_subject_count;
pub const witness_count = contract.witness_count;
pub const schema_version = contract.schema_version;
pub const isRequiredSubject = contract.isRequiredSubject;

/// How long an unexplained undercount has to persist before it is a defect
/// rather than an in-flight difference.
///
/// Witnesses do not report at the same instant. Rosette's tracepoint counts at
/// the function's first instruction and the emulator's line is printed a few
/// instructions later, so between one checkpoint and the next either can be
/// momentarily ahead. A gate with no settling window would stop a healthy run
/// on the ordinary skew between two correct counters. One tenth of a billion
/// steps is a full graphics checkpoint interval on the observed runs, so a
/// shortfall that survives it is not skew.
pub const settling_steps: u64 = 100_000_000;

pub const Summary = struct {
    observed: usize = 0,
    corroborated: usize = 0,
    explained: usize = 0,
    /// Subjects where a witness that sees everything is short. Each one makes
    /// every absence that witness reported unsafe to quote.
    unexplained: usize = 0,
    regressions: usize = 0,
    /// Subjects with exactly one witness. Not a defect, but the list of places
    /// where a second carrier would make an absence quotable.
    uncorroborated: usize = 0,
    statements: u64 = 0,
    /// The largest gap, in steps, between a short witness's last statement and
    /// the floor witness's. This is the "how stale" number.
    worst_quiet_steps: u64 = 0,
    worst_subject: ?Subject = null,
    /// Unexplained undercounts that have outlived the settling window. Only
    /// these are judgeable; the rest may still be two correct counters caught
    /// mid-stride.
    settled_unexplained: usize = 0,
    settled_subject: ?Subject = null,
    /// Unexplained undercounts that resolved themselves. Retained because a
    /// gate that only ever reports its current state cannot be audited for
    /// having been too eager.
    resolutions: u64 = 0,
    /// Required core subjects that have spoken at least once. The optional
    /// guest-frame subject is deliberately excluded from these counts.
    required_observed: usize = 0,
    /// Required core subjects whose finding is exactly corroborated. Explained
    /// or weak readings remain agreement debt: they still lack two independent
    /// agreeing observers even when their difference has a structural excuse.
    required_corroborated: usize = 0,
    /// Required core subjects that are observed but not exactly corroborated.
    /// This is intentionally stricter than `judgeableDefects()` and is used by
    /// the fail-fast closure gate.
    required_agreement_debt: usize = 0,
    /// Required core subjects whose every witness still reads zero.
    ///
    /// A tracepoint armed on an eligible, never-crossed boundary states a zero,
    /// and a zero is not a claim: it says the mechanism has not run and nobody
    /// else has looked either. Counting those toward closure let a run that had
    /// merely armed its tracepoints report all nine required subjects observed
    /// and every one of them in agreement debt — a stop demanding that a second
    /// observer corroborate nine statements nobody had made. Reported rather
    /// than silently skipped, because "no claim yet" and "corroborated" are
    /// opposite states and the closure line must not blur them.
    required_unclaimed: usize = 0,

    pub fn defects(self: Summary) usize {
        return self.unexplained + self.regressions;
    }

    /// What the run may be stopped for.
    pub fn judgeableDefects(self: Summary) usize {
        return self.settled_unexplained + self.regressions;
    }
};

/// How long one subject's unexplained undercount has been standing.
const Persistence = struct {
    unexplained_since: u64 = 0,
    resolutions: u32 = 0,
    floor_at_start: u64 = 0,
};

pub const Ledger = struct {
    readings: [subject_count][witness_count]Reading = blk: {
        var table: [subject_count][witness_count]Reading = undefined;
        for (&table) |*row| {
            for (row, 0..) |*cell, index| {
                cell.* = .{ .witness = @enumFromInt(index) };
            }
        }
        break :blk table;
    },
    persistence: [subject_count]Persistence = [_]Persistence{.{}} ** subject_count,
    statements: u64 = 0,
    /// The step of the most recent `settle`. Zero until the first one, which
    /// is what keeps a defect from being judgeable before anything has run.
    settled_step: u64 = 0,

    /// Record one witness's statement of the running total.
    ///
    /// `count` is the total the witness believes, not an increment. Every
    /// carrier in this codebase that is worth reconciling restates a total —
    /// a per-event line that carries no total is registered by counting the
    /// lines, which is exactly the carrier the contract refuses to trust.
    pub fn state(self: *Ledger, subject: Subject, witness: Witness, count: u64, step: u64) void {
        self.statements +|= 1;
        const cell = &self.readings[@intFromEnum(subject)][@intFromEnum(witness)];
        if (!cell.stated) {
            cell.stated = true;
            cell.first_step = step;
        }
        if (count < cell.count) {
            cell.regressions +|= 1;
        } else {
            cell.count = count;
        }
        cell.statements +|= 1;
        if (step >= cell.last_step) cell.last_step = step;
    }

    /// Record one occurrence from a witness that counts lines rather than
    /// restating a total.
    pub fn tick(self: *Ledger, subject: Subject, witness: Witness, step: u64) void {
        const cell = &self.readings[@intFromEnum(subject)][@intFromEnum(witness)];
        self.state(subject, witness, cell.count + 1, step);
    }

    pub fn reading(self: *const Ledger, subject: Subject, witness: Witness) Reading {
        return self.readings[@intFromEnum(subject)][@intFromEnum(witness)];
    }

    pub fn reconcile(self: *const Ledger, subject: Subject) Reconciliation {
        const row = &self.readings[@intFromEnum(subject)];
        var result = Reconciliation{ .subject = subject };
        result.finding = contract.classify(row);

        for (row) |cell| {
            if (!cell.stated) continue;
            result.witnesses += 1;
            if (cell.count > result.floor or result.floor_witness == null) {
                result.floor = cell.count;
                result.floor_witness = cell.witness;
                result.floor_step = cell.last_step;
            }
        }
        if (result.floor_witness == null) return result;

        for (row) |cell| {
            if (!cell.stated) continue;
            if (cell.count >= result.floor) continue;
            if (result.short_witness != null and cell.count >= result.short_count) continue;
            result.short_witness = cell.witness;
            result.short_count = cell.count;
            result.short_step = cell.last_step;
            result.short_quiet_steps = result.floor_step -| cell.last_step;
        }
        return result;
    }

    /// The count a report should print for this subject, and nothing if no
    /// witness has ever spoken. `null` is deliberately distinct from zero: a
    /// subject nobody counted is a hole, and a subject everybody counted as
    /// zero is a fact.
    pub fn floor(self: *const Ledger, subject: Subject) ?u64 {
        const result = self.reconcile(subject);
        if (result.floor_witness == null) return null;
        return result.floor;
    }

    /// Whether a reader may treat this subject's zero as an absence of the
    /// thing rather than an absence of the observation. This is the question
    /// the graphics evidence table was answering wrongly.
    pub fn absenceIsQuotable(self: *const Ledger, subject: Subject) bool {
        return self.reconcile(subject).finding.absenceIsQuotable();
    }

    /// Close one observation window.
    ///
    /// Called once per checkpoint, after every witness for this window has
    /// stated. It converts "these two counters differ right now" into "they
    /// have differed since step N", which is the only form the run-integrity
    /// gate is allowed to act on: two correct counters read a few instructions
    /// apart differ constantly and briefly, and a gate that stopped on that
    /// would be stopping on its own sampling.
    pub fn settle(self: *Ledger, step: u64) void {
        self.settled_step = step;
        var index: usize = 0;
        while (index < subject_count) : (index += 1) {
            const found = self.reconcile(@enumFromInt(index)).finding;
            const cell = &self.persistence[index];
            if (found == .undercount_unexplained) {
                if (cell.unexplained_since == 0) {
                    cell.unexplained_since = step;
                    cell.floor_at_start = self.reconcile(@enumFromInt(index)).floor;
                }
                continue;
            }
            if (cell.unexplained_since != 0) {
                cell.unexplained_since = 0;
                cell.resolutions +|= 1;
            }
        }
    }

    /// Whether this subject's unexplained undercount has outlived the settling
    /// window. A regression never needs to settle: a monotone counter going
    /// backwards is not a sampling artefact.
    pub fn settledDefect(self: *const Ledger, subject: Subject) bool {
        const found = self.reconcile(subject).finding;
        if (found == .regression) return true;
        if (found != .undercount_unexplained) return false;
        const since = self.persistence[@intFromEnum(subject)].unexplained_since;
        if (since == 0) return false;
        if (self.settled_step -| since < settling_steps) return false;
        // Silence from a throttled source is not a fresh low measurement.
        // Require a complete witness to restate a count below the floor that
        // was already known when this window opened, after that window.
        const baseline = self.persistence[@intFromEnum(subject)].floor_at_start;
        for (self.readings[@intFromEnum(subject)]) |reading_value| {
            if (reading_value.stated and reading_value.witness.countsEveryOccurrence() and
                reading_value.last_step > since and reading_value.count < baseline) return true;
        }
        return false;
    }

    pub fn summary(self: *const Ledger) Summary {
        var out = Summary{ .statements = self.statements };
        var index: usize = 0;
        while (index < subject_count) : (index += 1) {
            const subject: Subject = @enumFromInt(index);
            const result = self.reconcile(subject);
            switch (result.finding) {
                .unobserved => continue,
                .single_witness, .dependent_agreement => {
                    out.observed += 1;
                    out.uncorroborated += 1;
                },
                .corroborated => {
                    out.observed += 1;
                    out.corroborated += 1;
                },
                .undercount_explained, .weak_witness_exceeds => {
                    out.observed += 1;
                    out.explained += 1;
                },
                .undercount_unexplained => {
                    out.observed += 1;
                    out.unexplained += 1;
                },
                .regression => {
                    out.observed += 1;
                    out.regressions += 1;
                },
            }
            if (isRequiredSubject(subject)) {
                // A subject whose highest reading is still zero has made no
                // claim. Corroboration is agreement between observers about
                // something one of them saw; there is nothing here to agree
                // about, and demanding a second observer for it is a demand no
                // correct run can satisfy during bring-up.
                if (result.floor == 0) {
                    out.required_unclaimed += 1;
                } else {
                    out.required_observed += 1;
                    if (result.finding == .corroborated) {
                        out.required_corroborated += 1;
                    } else {
                        out.required_agreement_debt += 1;
                    }
                }
            }
            if (result.short_quiet_steps > out.worst_quiet_steps) {
                out.worst_quiet_steps = result.short_quiet_steps;
                out.worst_subject = subject;
            }
            out.resolutions +|= self.persistence[index].resolutions;
            if (self.settledDefect(subject) and result.finding == .undercount_unexplained) {
                out.settled_unexplained += 1;
                if (out.settled_subject == null) out.settled_subject = subject;
            }
        }
        return out;
    }

    /// The subject a reader should look at first: an unexplained undercount if
    /// there is one, otherwise the stalest explained one.
    pub fn firstDefect(self: *const Ledger) ?Reconciliation {
        var stalest: ?Reconciliation = null;
        var index: usize = 0;
        while (index < subject_count) : (index += 1) {
            const result = self.reconcile(@enumFromInt(index));
            if (result.isDefect()) return result;
            if (result.finding != .undercount_explained) continue;
            if (stalest == null or result.short_quiet_steps > stalest.?.short_quiet_steps) {
                stalest = result;
            }
        }
        return stalest;
    }

    pub fn fingerprint(self: *const Ledger) u64 {
        var hash: u64 = 0xcbf29ce484222325;
        var index: usize = 0;
        while (index < subject_count) : (index += 1) {
            const result = self.reconcile(@enumFromInt(index));
            hash ^= @as(u64, @intFromEnum(result.finding)) +% result.floor +% result.short_count;
            hash *%= 0x100000001b3;
        }
        return hash;
    }
};

test "the throttled callback breadcrumb no longer sets the callback count" {
    // Exactly the 2026-08-31 numbers. The completion breadcrumb stopped at
    // step 3_006_534_266 with four; the dispatch counter reached two hundred
    // and forty and was still speaking at 7_493_776_604.
    var ledger = Ledger{};
    ledger.state(.title_interrupt_callback_entries, .emulator_sampled_line, 4, 3_006_534_266);
    ledger.state(.title_interrupt_callback_entries, .emulator_sampled_total, 240, 7_493_776_604);

    const result = ledger.reconcile(.title_interrupt_callback_entries);
    try std.testing.expectEqual(Finding.undercount_explained, result.finding);
    try std.testing.expectEqual(@as(u64, 240), result.floor);
    try std.testing.expectEqual(Witness.emulator_sampled_total, result.floor_witness.?);
    try std.testing.expectEqual(Witness.emulator_sampled_line, result.short_witness.?);
    try std.testing.expectEqual(@as(u64, 4_487_242_338), result.short_quiet_steps);
    try std.testing.expectEqual(@as(u64, 240), ledger.floor(.title_interrupt_callback_entries).?);
    try std.testing.expect(!ledger.absenceIsQuotable(.title_interrupt_callback_entries));
    try std.testing.expect(!result.isDefect());
}

test "an armed tracepoint that is short of the emulator's counter is a defect" {
    var ledger = Ledger{};
    ledger.state(.render_target_updates, .rosette_tracepoint, 0, 7_400_000_000);
    ledger.state(.render_target_updates, .emulator_heartbeat_counter, 24, 7_400_000_000);

    const result = ledger.reconcile(.render_target_updates);
    try std.testing.expectEqual(Finding.undercount_unexplained, result.finding);
    try std.testing.expect(result.isDefect());
    try std.testing.expectEqual(@as(usize, 1), ledger.summary().unexplained);
    try std.testing.expectEqual(Finding.undercount_unexplained, ledger.firstDefect().?.finding);
}

test "an unobserved subject is a hole and not a zero" {
    const ledger = Ledger{};
    try std.testing.expect(ledger.floor(.guest_frames_presented) == null);
    try std.testing.expect(!ledger.absenceIsQuotable(.guest_frames_presented));
    try std.testing.expectEqual(@as(usize, 0), ledger.summary().observed);
    try std.testing.expect(ledger.firstDefect() == null);
}

test "an agreed subject makes its own zero quotable" {
    var ledger = Ledger{};
    ledger.state(.guest_frames_presented, .rosette_tracepoint, 0, 100);
    ledger.state(.guest_frames_presented, .emulator_heartbeat_counter, 0, 200);
    try std.testing.expect(ledger.absenceIsQuotable(.guest_frames_presented));
    try std.testing.expectEqual(@as(u64, 0), ledger.floor(.guest_frames_presented).?);
    try std.testing.expectEqual(@as(usize, 1), ledger.summary().corroborated);
}

test "a total that goes backwards is recorded and never lowers the floor" {
    var ledger = Ledger{};
    ledger.state(.pm4_packets_consumed, .emulator_sampled_total, 63, 100);
    ledger.state(.pm4_packets_consumed, .emulator_sampled_total, 7, 200);
    ledger.state(.pm4_packets_consumed, .rosette_tracepoint, 63, 200);

    const result = ledger.reconcile(.pm4_packets_consumed);
    try std.testing.expectEqual(Finding.regression, result.finding);
    try std.testing.expectEqual(@as(u64, 63), result.floor);
    try std.testing.expectEqual(@as(u64, 1), ledger.reading(.pm4_packets_consumed, .emulator_sampled_total).regressions);
    try std.testing.expect(result.isDefect());
}

test "ticking a line-counting witness accumulates without a stated total" {
    var ledger = Ledger{};
    var index: u64 = 0;
    while (index < 4) : (index += 1) ledger.tick(.draws_issued, .emulator_sampled_line, 1000 + index);
    ledger.state(.draws_issued, .rosette_tracepoint, 24, 2000);

    const result = ledger.reconcile(.draws_issued);
    try std.testing.expectEqual(@as(u64, 4), ledger.reading(.draws_issued, .emulator_sampled_line).count);
    try std.testing.expectEqual(@as(u64, 24), result.floor);
    try std.testing.expectEqual(Finding.undercount_explained, result.finding);
}

test "the fingerprint moves when a subject changes and not otherwise" {
    var ledger = Ledger{};
    const empty = ledger.fingerprint();
    ledger.state(.vblank_marks, .rosette_tracepoint, 410, 100);
    const one = ledger.fingerprint();
    try std.testing.expect(empty != one);
    ledger.state(.vblank_marks, .rosette_tracepoint, 410, 200);
    try std.testing.expectEqual(one, ledger.fingerprint());
}

test "an unexplained undercount is not judgeable until it has settled" {
    var ledger = Ledger{};
    ledger.state(.render_target_updates, .rosette_tracepoint, 23, 3_000_000_000);
    ledger.state(.render_target_updates, .emulator_heartbeat_counter, 24, 3_000_000_000);
    ledger.settle(3_000_000_000);
    try std.testing.expect(!ledger.settledDefect(.render_target_updates));
    try std.testing.expectEqual(@as(usize, 0), ledger.summary().judgeableDefects());

    // The tracepoint caught up one checkpoint later: this was sampling skew,
    // and the gate correctly declined to stop the run for it.
    ledger.state(.render_target_updates, .rosette_tracepoint, 24, 3_100_000_000);
    ledger.settle(3_100_000_000);
    try std.testing.expect(!ledger.settledDefect(.render_target_updates));
    try std.testing.expectEqual(@as(u64, 1), ledger.summary().resolutions);
}

test "an unexplained undercount that outlives the window is judgeable" {
    var ledger = Ledger{};
    ledger.state(.pm4_packets_consumed, .rosette_tracepoint, 0, 3_000_000_000);
    ledger.state(.pm4_packets_consumed, .emulator_heartbeat_counter, 63, 3_000_000_000);
    ledger.settle(3_000_000_000);
    try std.testing.expect(!ledger.settledDefect(.pm4_packets_consumed));

    ledger.state(.pm4_packets_consumed, .rosette_tracepoint, 0, 3_100_000_000);
    ledger.state(.pm4_packets_consumed, .emulator_heartbeat_counter, 63, 3_100_000_000);
    ledger.settle(3_100_000_000);
    try std.testing.expect(ledger.settledDefect(.pm4_packets_consumed));
    const out = ledger.summary();
    try std.testing.expectEqual(@as(usize, 1), out.settled_unexplained);
    try std.testing.expectEqual(Subject.pm4_packets_consumed, out.settled_subject.?);
    try std.testing.expectEqual(@as(usize, 1), out.judgeableDefects());
}

test "a regression is judgeable immediately" {
    var ledger = Ledger{};
    ledger.state(.draws_issued, .emulator_sampled_total, 24, 100);
    ledger.state(.draws_issued, .emulator_sampled_total, 3, 200);
    ledger.settle(200);
    try std.testing.expect(ledger.settledDefect(.draws_issued));
    try std.testing.expectEqual(@as(usize, 1), ledger.summary().judgeableDefects());
}

test "an explained undercount never becomes judgeable however long it lasts" {
    var ledger = Ledger{};
    ledger.state(.draws_issued, .emulator_sampled_line, 5, 3_259_971_460);
    ledger.state(.draws_issued, .rosette_tracepoint, 24, 3_260_346_355);
    var step: u64 = 3_300_000_000;
    while (step < 7_500_000_000) : (step += 100_000_000) {
        ledger.state(.draws_issued, .rosette_tracepoint, 24, step);
        ledger.settle(step);
    }
    const result = ledger.reconcile(.draws_issued);
    try std.testing.expectEqual(Finding.undercount_explained, result.finding);
    try std.testing.expectEqual(@as(u64, 24), result.floor);
    try std.testing.expect(!ledger.settledDefect(.draws_issued));
    try std.testing.expectEqual(@as(usize, 0), ledger.summary().judgeableDefects());
    try std.testing.expectEqual(@as(usize, 1), ledger.summary().explained);
}

test "pre-gate dispatch calls and admitted executor calls are different subjects" {
    var ledger = Ledger{};
    ledger.state(.graphics_interrupt_dispatches, .rosette_tracepoint, 128, 3_000_000_000);
    ledger.state(.interrupt_executor_entries, .emulator_sampled_total, 3, 2_989_655_234);
    ledger.state(.pm4_packets_consumed, .rosette_tracepoint, 1, 3_000_000_000);
    ledger.state(.pm4_packets_all_types, .emulator_sampled_total, 19, 2_900_000_000);
    ledger.settle(3_000_000_000);
    ledger.settle(3_100_000_000);
    try std.testing.expectEqual(@as(usize, 0), ledger.summary().judgeableDefects());
    try std.testing.expectEqual(@as(u64, 128), ledger.floor(.graphics_interrupt_dispatches).?);
    try std.testing.expectEqual(@as(u64, 3), ledger.floor(.interrupt_executor_entries).?);
    try std.testing.expect(!ledger.absenceIsQuotable(.graphics_interrupt_dispatches));
}

test "a stale sampled total cannot become a settled counter defect" {
    var ledger = Ledger{};
    ledger.state(.draws_issued, .emulator_sampled_total, 4, 100);
    ledger.state(.draws_issued, .rosette_tracepoint, 24, 200);
    ledger.settle(200);
    ledger.state(.draws_issued, .rosette_tracepoint, 30, 200 + settling_steps);
    ledger.settle(200 + settling_steps);
    try std.testing.expect(!ledger.settledDefect(.draws_issued));
    ledger.state(.draws_issued, .emulator_sampled_total, 4, 201 + settling_steps);
    ledger.settle(201 + settling_steps);
    try std.testing.expect(ledger.settledDefect(.draws_issued));
}

// 2026-09-04: seven tracepoints were armed on eligible, never-crossed
// boundaries and each stated a zero. Those zeroes counted as observations, the
// required set reached closure, and every subject was in agreement debt — a
// stop demanding a second observer for nine statements nobody had made.
test "a zero from one witness is not a claim to corroborate" {
    var ledger = Ledger{};
    // Every required subject, stated once, all reading zero.
    inline for (@typeInfo(Subject).@"enum".fields) |field| {
        const subject: Subject = @enumFromInt(field.value);
        if (isRequiredSubject(subject)) {
            ledger.state(subject, .rosette_tracepoint, 0, 10);
        }
    }
    var totals = ledger.summary();
    try std.testing.expectEqual(required_subject_count, totals.required_unclaimed);
    // Nothing has been claimed, so nothing is owed corroboration and the set
    // has not closed.
    try std.testing.expectEqual(@as(usize, 0), totals.required_observed);
    try std.testing.expectEqual(@as(usize, 0), totals.required_agreement_debt);

    // A real claim from a single witness is agreement debt, which is the state
    // the gate exists to catch.
    ledger.state(.draws_issued, .rosette_tracepoint, 2, 20);
    totals = ledger.summary();
    try std.testing.expectEqual(@as(usize, 1), totals.required_observed);
    try std.testing.expectEqual(@as(usize, 1), totals.required_agreement_debt);
    try std.testing.expectEqual(required_subject_count - 1, totals.required_unclaimed);

    // A second observer that agrees clears the debt.
    ledger.state(.draws_issued, .emulator_sampled_total, 2, 21);
    totals = ledger.summary();
    try std.testing.expectEqual(@as(usize, 1), totals.required_corroborated);
    try std.testing.expectEqual(@as(usize, 0), totals.required_agreement_debt);
}
