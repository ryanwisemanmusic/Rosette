//! One transaction per pause, opened before the guest stops and closed only
//! when it resumes or the run ends.
//!
//! The defect this exists for
//! --------------------------
//! The 2026-08-31 log contains, at line 25 645:
//!
//! ```text
//! GPU PRODUCER PAUSED: ... Xenia has intentionally paused guest execution ...
//! Inspect the preceding GUEST FAULT FRONTIER for the first missing transition.
//! ```
//!
//! There is no preceding `GUEST FAULT FRONTIER` in the log. No `EMULATOR
//! PAUSED` and no `EMULATOR RESUMED` either. The line is emitted from a branch
//! that tests `is_paused_due_to_guest_fault()`, and the code that sets that
//! flag also writes the frontier — so either the frontier record was dropped,
//! or the flag was read from a path that did not set it.
//!
//! That ambiguity is not a logging nuisance. A pause changes the meaning of
//! every wait and quiet period after it. If the guest was paused before the
//! producer's first 30 ms poll, the poll is a consequence; if it was not, the
//! poll may be the cause. Reading the log in the wrong order costs the whole
//! investigation.
//!
//! The rule
//! --------
//! A pause has exactly one cause transaction, and a `paused` report with no
//! matching transaction is `unreconciled` — never a root cause. The run ends
//! in exactly one of four states, and a run-integrity termination is not a
//! guest fault however loud its signal is.

const std = @import("std");
const bridge = @import("rosette_graphics_bridge");

pub const CodeLocation = bridge.contract.CodeLocation;
pub const Address = bridge.contract.Address;

/// What stopped the guest.
pub const Cause = enum(u8) {
    /// A guest memory access, illegal instruction, or other guest-visible
    /// fault the emulator chose to stop on.
    guest_fault = 0,
    /// A person or a script asked for it.
    user_request = 1,
    /// A diagnostic tool paused to sample.
    diagnostic_hold = 2,
    /// The emulator paused itself for its own bookkeeping.
    emulator_internal = 3,
    unknown = 255,

    pub fn label(self: Cause) []const u8 {
        return switch (self) {
            .guest_fault => "guest-fault",
            .user_request => "user-request",
            .diagnostic_hold => "diagnostic-hold",
            .emulator_internal => "emulator-internal",
            .unknown => "unknown",
        };
    }

    /// Whether waits observed after this pause may still be read as the
    /// guest's own behaviour.
    pub fn suspendsGuestCausality(self: Cause) bool {
        return self != .unknown;
    }
};

/// How the run finished. Four states, and the audit's point is that a
/// deliberate diagnostic termination must never be filed as the third.
pub const Termination = enum(u8) {
    /// Still going.
    running = 0,
    /// The guest faulted and the emulator paused on it.
    guest_fault_paused = 1,
    /// A person stopped it.
    user_pause = 2,
    /// A gate stopped it on purpose — a run-integrity invariant, a watchdog,
    /// a budget. The signal it raises is a policy, not a crash.
    diagnostic_termination = 3,
    /// The title or the harness exited normally.
    normal_exit = 4,

    pub fn label(self: Termination) []const u8 {
        return switch (self) {
            .running => "running",
            .guest_fault_paused => "guest-fault-paused",
            .user_pause => "user-pause",
            .diagnostic_termination => "diagnostic-termination",
            .normal_exit => "normal-exit",
        };
    }

    pub fn describe(self: Termination) []const u8 {
        return switch (self) {
            .running => "the run has not ended",
            .guest_fault_paused => "the guest faulted and the emulator paused on it. Every wait and quiet period after the pause step is a consequence of it",
            .user_pause => "a person or a script paused the run. Nothing after the pause describes the title's own behaviour",
            .diagnostic_termination => "a gate stopped the run deliberately. The signal it raised is a policy decision and is not evidence that the guest crashed — read the gate's own report for what it stopped for",
            .normal_exit => "the run ended without a fault or a gate stopping it",
        };
    }

    /// Whether the run's end may be quoted as the guest crashing.
    pub fn isGuestCrash(self: Termination) bool {
        return self == .guest_fault_paused;
    }
};

/// The stages one transaction passes through. Nothing is inferred: a pause
/// completion does not imply a pause request was recorded, because the exact
/// failure being caught is a completion whose request went missing.
pub const Stage = enum(u8) {
    fault_recorded = 0,
    pause_requested = 1,
    pause_completed = 2,
    resume_requested = 3,
    resume_completed = 4,

    pub fn label(self: Stage) []const u8 {
        return switch (self) {
            .fault_recorded => "fault recorded",
            .pause_requested => "pause requested",
            .pause_completed => "pause completed",
            .resume_requested => "resume requested",
            .resume_completed => "resume completed",
        };
    }
};

pub const stage_count: usize = @typeInfo(Stage).@"enum".fields.len;

/// A pause report can be structurally present and still fail to identify the
/// transaction it claims to describe. Keep those protocol failures separate
/// from the standing (`unreconciled`, `cause_missing`, ...) so the report can
/// say whether Rosette lost a record, Xenia emitted an impossible bracket, or
/// two sides attached different transactions to the same pause.
pub const ProtocolDefect = enum(u8) {
    none,
    malformed_external_transaction,
    external_transaction_without_frontier,
    external_transaction_mismatch,
    producer_pause_without_transaction,
    producer_pause_unreconciled,
    resume_without_transaction,

    pub fn label(self: ProtocolDefect) []const u8 {
        return switch (self) {
            .none => "none",
            .malformed_external_transaction => "malformed-external-transaction",
            .external_transaction_without_frontier => "external-transaction-without-frontier",
            .external_transaction_mismatch => "external-transaction-mismatch",
            .producer_pause_without_transaction => "producer-pause-without-transaction",
            .producer_pause_unreconciled => "producer-pause-unreconciled",
            .resume_without_transaction => "resume-without-transaction",
        };
    }
};

/// A complete pause transaction.
pub const Transaction = struct {
    id: u64 = 0,
    /// Xenia's transaction identity. `id` is Rosette's local retained-slot
    /// identity; these namespaces must never be conflated just because both
    /// commonly start at one.
    external_id: u64 = 0,
    external_id_step: u64 = 0,
    cause: Cause = .unknown,
    /// The signal or exception code, when there was one.
    signal_code: u32 = 0,
    guest_thread: u64 = 0,
    xthread_handle: u32 = 0,
    location: CodeLocation = .{},
    /// The faulting access, when applicable.
    fault_address: Address = .{},
    /// 0 read, 1 write, 2 execute. Only meaningful for a memory fault.
    access_kind: u8 = 0,
    module_id: u32 = 0,
    /// The producer's epoch at the moment of the pause, so the two ledgers can
    /// be read against one sequence number rather than two clocks.
    producer_epoch: u8 = 0,
    wait_object: u64 = 0,
    ring_read_index: u32 = 0,
    ring_write_index: u32 = 0,
    last_packet_opcode: u32 = 0,
    reached: [stage_count]bool = [_]bool{false} ** stage_count,
    step: [stage_count]u64 = [_]u64{0} ** stage_count,

    pub fn note(self: *Transaction, stage: Stage, at_step: u64) void {
        const index = @intFromEnum(stage);
        if (!self.reached[index]) self.step[index] = at_step;
        self.reached[index] = true;
    }

    pub fn has(self: Transaction, stage: Stage) bool {
        return self.reached[@intFromEnum(stage)];
    }

    pub fn open(self: Transaction) bool {
        return self.has(.pause_completed) and !self.has(.resume_completed);
    }

    /// A transaction that never recorded its cause cannot explain anything,
    /// however complete the rest of it is.
    pub fn causeProven(self: Transaction) bool {
        return self.has(.fault_recorded) and self.cause != .unknown;
    }

    pub fn pauseStep(self: Transaction) u64 {
        return self.step[@intFromEnum(Stage.pause_completed)];
    }

    /// Attach Xenia's identity exactly once. A changed identity is a protocol
    /// violation, not a later snapshot that may silently replace the first.
    pub fn noteExternalId(self: *Transaction, external_id: u64, at_step: u64) bool {
        if (external_id == 0) return false;
        if (self.external_id != 0 and self.external_id != external_id) return false;
        if (self.external_id == 0) {
            self.external_id = external_id;
            self.external_id_step = at_step;
        }
        return true;
    }
};

/// A monotone reading a paused guest cannot advance.
///
/// A pause report says the guest stopped. That claim is refutable, and until
/// it is refuted every wait in the run is filed as a consequence of a pause
/// nobody can point at. The axes below are the evidence: each one only moves
/// because guest instructions ran, so a reading higher than the one taken when
/// the report was made is proof the guest was executing after it.
///
/// Deliberately not the executed-step counter. A spin loop advances that, and
/// an axis a spin can advance cannot refute anything.
pub const ProgressAxis = enum(u8) {
    /// New guest functions translated. A translation happens because guest
    /// code was reached for the first time.
    guest_code_translated = 0,
    /// Waiters that blocked and were released. A release needs a guest thread
    /// to have run and signalled.
    guest_wait_released = 1,
    /// Distinct guest exports entered. Each one is a new call the title made.
    guest_export_entered = 2,
    /// Distinct guest symbols reached. The broadest axis, and still one a
    /// stopped guest cannot move.
    guest_symbol_reached = 3,

    pub fn label(self: ProgressAxis) []const u8 {
        return switch (self) {
            .guest_code_translated => "guest-code-translated",
            .guest_wait_released => "guest-wait-released",
            .guest_export_entered => "guest-export-entered",
            .guest_symbol_reached => "guest-symbol-reached",
        };
    }

    /// Why a paused guest cannot advance this. Stated per axis so a reader can
    /// check the argument rather than take the refutation on trust.
    pub fn whyPausedGuestCannotAdvanceIt(self: ProgressAxis) []const u8 {
        return switch (self) {
            .guest_code_translated => "a function is translated because guest code reached it for the first time, which requires the guest to be executing",
            .guest_wait_released => "a waiter leaves its blocked state because another guest thread signalled, which requires that thread to be executing",
            .guest_export_entered => "an export is entered because the title called it, which requires the title to be executing",
            .guest_symbol_reached => "a new symbol is reached because control arrived there, which requires the guest to be executing",
        };
    }
};

pub const progress_axis_count: usize = @typeInfo(ProgressAxis).@"enum".fields.len;

/// What the ledger concluded about the run's pause state.
pub const Standing = enum(u8) {
    /// No pause has been reported by anyone.
    never_paused,
    /// A transaction exists and completed. The pause is explained.
    reconciled,
    /// A pause is open and its cause is recorded. Reading is possible.
    open_with_cause,
    /// Something reported a pause and no transaction exists for it. The
    /// report may not be used as a cause, and no wait after it may be read as
    /// the guest's own behaviour either.
    unreconciled,
    /// A transaction exists with no cause recorded.
    cause_missing,
    /// A pause was reported, no transaction exists for it, and the guest has
    /// demonstrably executed since. The claim is disproved.
    report_refuted,

    pub fn label(self: Standing) []const u8 {
        return switch (self) {
            .never_paused => "never-paused",
            .reconciled => "reconciled",
            .open_with_cause => "open-with-cause",
            .unreconciled => "UNRECONCILED",
            .cause_missing => "CAUSE-MISSING",
            .report_refuted => "REPORT-REFUTED",
        };
    }

    pub fn describe(self: Standing) []const u8 {
        return switch (self) {
            .never_paused => "nothing has reported a pause. Waits and quiet periods describe the guest's own behaviour",
            .reconciled => "every pause report has a matching transaction that opened and closed. The intervals it covers are known",
            .open_with_cause => "a pause is open and its cause is recorded. Everything observed after its step is inside the pause",
            .unreconciled => "something reported that the guest was paused and no transaction exists for it. This report is not a root cause, and no wait observed after it may be read as the guest's own behaviour until the transaction is found or the report is proven wrong",
            .cause_missing => "a pause transaction exists and never recorded what caused it. The interval is known and the reason is not",
            .report_refuted => "a pause was reported with no transaction behind it, and the guest has executed since. The claim is disproved rather than merely unmatched: waits after it describe the guest's own behaviour again, and the defect is in whatever printed the report",
        };
    }

    pub fn isDefect(self: Standing) bool {
        return self == .unreconciled or self == .cause_missing or self == .report_refuted;
    }

    /// Whether guest waits observed in this run may be read as the guest's own.
    ///
    /// A refuted report restores this. Leaving it suspended would let one
    /// unmatched line disqualify every wait finding for the rest of the run —
    /// which is exactly what happened when the only way out of `unreconciled`
    /// was finding a transaction that was never written.
    pub fn guestCausalityIntact(self: Standing) bool {
        return self == .never_paused or self == .reconciled or self == .report_refuted;
    }

    /// Who the defect belongs to. A refuted report is a defect in the reporter,
    /// not in the guest and not in the pause machinery.
    pub fn owner(self: Standing) []const u8 {
        return switch (self) {
            .never_paused, .reconciled, .open_with_cause => "-",
            .unreconciled => "whoever printed the pause report",
            .cause_missing => "the pause machinery that opened a transaction without a cause",
            .report_refuted => "whoever printed the pause report: the guest was running when it claimed otherwise",
        };
    }
};

pub const max_transactions: usize = 16;

pub const Ledger = struct {
    transactions: [max_transactions]Transaction = [_]Transaction{.{}} ** max_transactions,
    count: usize = 0,
    dropped: u64 = 0,
    next_id: u64 = 1,
    /// Reports that said the guest was paused, from any source.
    pause_reports: u64 = 0,
    /// Reports with no transaction to match. The number the audit asks for.
    unmatched_reports: u64 = 0,
    /// A report or bracket carried an impossible transaction identity. This is
    /// distinct from an unmatched report because a non-zero ID can still be
    /// emitted without the frontier that would make it meaningful.
    protocol_defects: u64 = 0,
    last_protocol_defect: ProtocolDefect = .none,
    last_protocol_defect_step: u64 = 0,
    last_protocol_expected_id: u64 = 0,
    last_protocol_observed_id: u64 = 0,
    /// A transaction line can arrive before the frontier line in an interleaved
    /// log. Hold it briefly so the normal ordering still attaches the external
    /// identity instead of manufacturing a second local transaction.
    pending_external_id: u64 = 0,
    pending_external_id_step: u64 = 0,
    /// The step of the most recent unmatched report, and the progress readings
    /// as they stood when it was made. Everything about the refutation is a
    /// comparison against these.
    unmatched_report_step: u64 = 0,
    axis_at_report: [progress_axis_count]u64 = [_]u64{0} ** progress_axis_count,
    axis_latest: [progress_axis_count]u64 = [_]u64{0} ** progress_axis_count,
    /// The axis that disproved the report, if one has.
    refuted_by: ?ProgressAxis = null,
    refuted_step: u64 = 0,
    /// How far the axis moved past its value at report time. A margin of one
    /// is a refutation; a large margin says how long the run spent under a
    /// suppression that was never true.
    refutation_margin: u64 = 0,
    termination: Termination = .running,
    termination_step: u64 = 0,

    fn noteProtocol(
        self: *Ledger,
        defect: ProtocolDefect,
        at_step: u64,
        expected_id: u64,
        observed_id: u64,
    ) void {
        self.protocol_defects +|= 1;
        self.last_protocol_defect = defect;
        self.last_protocol_defect_step = at_step;
        self.last_protocol_expected_id = expected_id;
        self.last_protocol_observed_id = observed_id;
    }

    pub fn noteProtocolDefect(
        self: *Ledger,
        defect: ProtocolDefect,
        at_step: u64,
        expected_id: u64,
        observed_id: u64,
    ) void {
        self.noteProtocol(defect, at_step, expected_id, observed_id);
    }

    fn recordUnmatchedReport(self: *Ledger, at_step: u64) void {
        self.unmatched_reports +|= 1;
        self.unmatched_report_step = at_step;
        self.axis_at_report = self.axis_latest;
        // A new report reopens the question: whatever refuted the last one
        // says nothing about this one.
        self.refuted_by = null;
        self.refuted_step = 0;
        self.refutation_margin = 0;
    }

    pub fn begin(self: *Ledger, cause: Cause, at_step: u64) ?*Transaction {
        if (self.count >= max_transactions) {
            self.dropped +|= 1;
            return null;
        }
        const slot = &self.transactions[self.count];
        self.count += 1;
        slot.* = .{ .id = self.next_id, .cause = cause };
        self.next_id += 1;
        if (cause != .unknown) slot.note(.fault_recorded, at_step);
        if (self.pending_external_id != 0) {
            const external_id = self.pending_external_id;
            self.pending_external_id = 0;
            self.pending_external_id_step = 0;
            if (cause == .guest_fault and slot.noteExternalId(external_id, at_step)) {
                // The producer's line arrived before the frontier. The local
                // transaction is now the same one, so no defect is recorded.
            } else {
                self.noteProtocol(
                    .external_transaction_without_frontier,
                    at_step,
                    slot.id,
                    external_id,
                );
            }
        }
        return slot;
    }

    pub fn current(self: *Ledger) ?*Transaction {
        var index: usize = self.count;
        while (index > 0) {
            index -= 1;
            // The frontier is recorded before `pause_completed`. Matching
            // only fully-open transactions used to make EMULATOR PAUSED open a
            // second synthetic internal transaction and left the real fault
            // frontier detached from the pause it caused.
            if (!self.transactions[index].has(.resume_completed)) {
                return &self.transactions[index];
            }
        }
        return null;
    }

    /// Attach the emulator's transaction identity to the active guest-fault
    /// frontier. If the line arrives first, retain it until `begin` sees the
    /// frontier; if it arrives after the transaction has closed, the missing
    /// bracket is itself a protocol defect.
    pub fn noteExternalTransaction(self: *Ledger, external_id: u64, at_step: u64) void {
        if (external_id == 0) {
            self.noteProtocol(.malformed_external_transaction, at_step, 0, 0);
            return;
        }
        if (self.current()) |transaction| {
            if (transaction.cause != .guest_fault or
                !transaction.noteExternalId(external_id, at_step))
            {
                self.noteProtocol(
                    .external_transaction_mismatch,
                    at_step,
                    transaction.external_id,
                    external_id,
                );
            }
            return;
        }
        if (self.pending_external_id != 0) {
            if (self.pending_external_id != external_id) {
                self.noteProtocol(
                    .external_transaction_mismatch,
                    at_step,
                    self.pending_external_id,
                    external_id,
                );
            }
            return;
        }
        self.pending_external_id = external_id;
        self.pending_external_id_step = at_step;
    }

    pub fn noteMalformedExternalTransaction(self: *Ledger, at_step: u64) void {
        self.noteProtocol(.malformed_external_transaction, at_step, 0, 0);
    }

    /// Somebody printed that the guest is paused. Matched against an open
    /// transaction; unmatched reports are the finding.
    ///
    /// The step and the progress readings at that moment are kept because an
    /// unmatched report is a *claim*, and a claim needs a baseline before it
    /// can be checked.
    pub fn observePauseReport(self: *Ledger, at_step: u64) void {
        _ = self.observePauseReportWithMetadataInternal(at_step, 0, true, false);
    }

    /// Observe a producer report that carries the external transaction ID and
    /// Xenia's own reconciliation bit. A zero ID or `reconciled=NO` is fatal
    /// protocol evidence even when a local transaction happens to be present:
    /// the producer has not supplied a claim Rosette can independently join.
    pub fn observePauseReportWithMetadata(
        self: *Ledger,
        at_step: u64,
        external_id: u64,
        reconciled: bool,
    ) bool {
        return self.observePauseReportWithMetadataInternal(at_step, external_id, reconciled, true);
    }

    fn observePauseReportWithMetadataInternal(
        self: *Ledger,
        at_step: u64,
        external_id: u64,
        reconciled: bool,
        enforce_metadata: bool,
    ) bool {
        self.pause_reports +|= 1;
        const transaction = self.current() orelse {
            self.recordUnmatchedReport(at_step);
            if (enforce_metadata) {
                self.noteProtocol(
                    if (external_id == 0)
                        .producer_pause_without_transaction
                    else
                        .external_transaction_without_frontier,
                    at_step,
                    0,
                    external_id,
                );
            }
            return false;
        };

        var valid = true;
        if (enforce_metadata) {
            if (transaction.cause != .guest_fault) {
                self.noteProtocol(
                    .external_transaction_mismatch,
                    at_step,
                    transaction.external_id,
                    external_id,
                );
                valid = false;
            } else if (external_id == 0) {
                self.noteProtocol(
                    .producer_pause_without_transaction,
                    at_step,
                    transaction.external_id,
                    external_id,
                );
                valid = false;
            } else if (!transaction.noteExternalId(external_id, at_step)) {
                self.noteProtocol(
                    .external_transaction_mismatch,
                    at_step,
                    transaction.external_id,
                    external_id,
                );
                valid = false;
            }
            if (!reconciled) {
                self.noteProtocol(
                    .producer_pause_unreconciled,
                    at_step,
                    transaction.external_id,
                    external_id,
                );
                valid = false;
            }
        }
        transaction.note(.pause_completed, at_step);
        return valid;
    }

    /// Offer a monotone progress reading. Non-decreasing per axis; a lower
    /// value is a resend and is ignored rather than treated as a regression.
    ///
    /// When an unmatched pause report is standing and a reading rises above
    /// where it stood at report time, the guest executed after the report and
    /// the report is disproved.
    pub fn observeGuestProgress(
        self: *Ledger,
        axis: ProgressAxis,
        value: u64,
        at_step: u64,
    ) void {
        const slot = &self.axis_latest[@intFromEnum(axis)];
        if (value <= slot.*) return;
        slot.* = value;
        if (self.unmatched_reports == 0) return;
        if (at_step <= self.unmatched_report_step) return;
        const baseline = self.axis_at_report[@intFromEnum(axis)];
        if (value <= baseline) return;
        const margin = value - baseline;
        // The strongest refutation wins, so the report is judged against the
        // axis that moved furthest rather than the one that happened to
        // arrive first.
        if (self.refuted_by != null and margin <= self.refutation_margin) return;
        self.refuted_by = axis;
        self.refuted_step = at_step;
        self.refutation_margin = margin;
    }

    pub fn noteTermination(self: *Ledger, how: Termination, at_step: u64) void {
        self.termination = how;
        self.termination_step = at_step;
    }

    pub fn standing(self: *const Ledger) Standing {
        if (self.count == 0) {
            if (self.pause_reports == 0) return .never_paused;
            return if (self.refuted_by != null) .report_refuted else .unreconciled;
        }
        if (self.unmatched_reports != 0) {
            return if (self.refuted_by != null) .report_refuted else .unreconciled;
        }
        var index: usize = 0;
        var any_open = false;
        while (index < self.count) : (index += 1) {
            const transaction = self.transactions[index];
            if (!transaction.causeProven()) return .cause_missing;
            if (transaction.open()) any_open = true;
        }
        return if (any_open) .open_with_cause else .reconciled;
    }

    /// Return the number of pause-causality defects that must be carried into
    /// a run-integrity observation. The ledger keeps the detailed standing
    /// separately, but a dropped transaction is itself a defect even when no
    /// pause report remains to make `standing()` non-clean.
    pub fn defectCount(self: *const Ledger) u64 {
        var defects = self.dropped +| self.protocol_defects;
        if (self.pending_external_id != 0) defects +|= 1;
        for (self.transactions[0..self.count]) |transaction| {
            if (transaction.has(.pause_requested) and !transaction.has(.pause_completed)) {
                defects +|= 1;
            }
        }
        if (self.standing().isDefect()) defects +|= 1;
        return defects;
    }

    /// Whether an observation at `step` falls inside a pause. This is the
    /// question every wait report has to ask before claiming the guest chose
    /// to wait.
    pub fn insidePause(self: *const Ledger, step: u64) bool {
        var index: usize = 0;
        while (index < self.count) : (index += 1) {
            const transaction = self.transactions[index];
            const started = transaction.pauseStep();
            if (started == 0 or step < started) continue;
            if (!transaction.has(.resume_completed)) return true;
            if (step <= transaction.step[@intFromEnum(Stage.resume_completed)]) return true;
        }
        return false;
    }

    pub fn retained(self: *const Ledger) []const Transaction {
        return self.transactions[0..self.count];
    }
};

test "a pause report with no transaction is unreconciled and never a cause" {
    var ledger = Ledger{};
    // Exactly the 2026-08-31 shape: the warning printed, the frontier absent.
    ledger.observePauseReport(3_402_556_936);
    const standing = ledger.standing();
    try std.testing.expectEqual(Standing.unreconciled, standing);
    try std.testing.expect(standing.isDefect());
    try std.testing.expect(!standing.guestCausalityIntact());
    try std.testing.expectEqual(@as(u64, 1), ledger.unmatched_reports);
    try std.testing.expect(std.mem.indexOf(u8, standing.describe(), "not a root cause") != null);
    try std.testing.expectEqual(@as(u64, 1), ledger.defectCount());
}

test "a complete transaction reconciles the report and bounds the interval" {
    var ledger = Ledger{};
    const transaction = ledger.begin(.guest_fault, 3_100_000_000).?;
    transaction.note(.pause_requested, 3_100_000_100);
    transaction.note(.pause_completed, 3_100_000_200);
    ledger.observePauseReport(3_100_000_300);
    try std.testing.expectEqual(Standing.open_with_cause, ledger.standing());
    try std.testing.expect(ledger.insidePause(3_200_000_000));
    try std.testing.expect(!ledger.insidePause(3_000_000_000));

    const open = ledger.current().?;
    open.note(.resume_requested, 3_300_000_000);
    open.note(.resume_completed, 3_300_000_100);
    try std.testing.expectEqual(Standing.reconciled, ledger.standing());
    try std.testing.expect(ledger.standing().guestCausalityIntact());
    try std.testing.expect(!ledger.insidePause(3_400_000_000));
    try std.testing.expect(ledger.insidePause(3_250_000_000));
}

test "the producer transaction id joins a guest fault pause" {
    var ledger = Ledger{};
    const transaction = ledger.begin(.guest_fault, 100).?;
    transaction.note(.pause_requested, 101);
    ledger.noteExternalTransaction(77, 102);
    try std.testing.expectEqual(@as(u64, 77), transaction.external_id);
    try std.testing.expect(ledger.observePauseReportWithMetadata(103, 77, true));
    try std.testing.expectEqual(Standing.open_with_cause, ledger.standing());
    try std.testing.expectEqual(@as(u64, 0), ledger.protocol_defects);
    try std.testing.expectEqual(@as(u64, 0), ledger.defectCount());
}

test "a transaction id may precede its fault frontier" {
    var ledger = Ledger{};
    ledger.noteExternalTransaction(91, 10);
    const transaction = ledger.begin(.guest_fault, 11).?;
    try std.testing.expectEqual(@as(u64, 91), transaction.external_id);
    transaction.note(.pause_requested, 12);
    try std.testing.expect(ledger.observePauseReportWithMetadata(13, 91, true));
    try std.testing.expectEqual(@as(u64, 0), ledger.protocol_defects);
}

test "a zero or unreconciled producer pause is a protocol defect" {
    var ledger = Ledger{};
    try std.testing.expect(!ledger.observePauseReportWithMetadata(20, 0, false));
    try std.testing.expectEqual(ProtocolDefect.producer_pause_without_transaction, ledger.last_protocol_defect);
    try std.testing.expectEqual(@as(u64, 1), ledger.protocol_defects);
    // The missing transaction and the impossible producer metadata are two
    // distinct facts, so both are retained in the integrity count.
    try std.testing.expectEqual(@as(u64, 2), ledger.defectCount());
}

test "a producer pause with a different transaction id cannot close the fault" {
    var ledger = Ledger{};
    const transaction = ledger.begin(.guest_fault, 30).?;
    transaction.note(.pause_requested, 31);
    ledger.noteExternalTransaction(92, 32);
    try std.testing.expect(!ledger.observePauseReportWithMetadata(33, 93, true));
    try std.testing.expectEqual(@as(u64, 92), transaction.external_id);
    try std.testing.expectEqual(ProtocolDefect.external_transaction_mismatch, ledger.last_protocol_defect);
    try std.testing.expectEqual(@as(u64, 1), ledger.protocol_defects);
}

test "a transaction with no cause is a different defect from a missing one" {
    var ledger = Ledger{};
    const transaction = ledger.begin(.unknown, 100).?;
    transaction.note(.pause_completed, 110);
    const standing = ledger.standing();
    try std.testing.expectEqual(Standing.cause_missing, standing);
    try std.testing.expect(standing.isDefect());
    try std.testing.expect(!transaction.causeProven());
}

// The final SIGSEGV in the observed run came from the Rosette run-integrity
// gate after a bounded-poll invariant was violated. Filing that as a guest
// crash sends the next reader into the JIT symbol the crash report names.
test "a diagnostic termination is never a guest crash" {
    var ledger = Ledger{};
    ledger.noteTermination(.diagnostic_termination, 7_500_000_000);
    try std.testing.expect(!ledger.termination.isGuestCrash());
    try std.testing.expectEqual(Standing.never_paused, ledger.standing());
    try std.testing.expect(std.mem.indexOf(u8, Termination.diagnostic_termination.describe(), "not evidence") != null);

    ledger.noteTermination(.guest_fault_paused, 7_500_000_000);
    try std.testing.expect(ledger.termination.isGuestCrash());
}

test "nothing reported and nothing recorded is intact rather than clean" {
    const ledger = Ledger{};
    try std.testing.expectEqual(Standing.never_paused, ledger.standing());
    try std.testing.expect(ledger.standing().guestCausalityIntact());
    try std.testing.expect(!ledger.insidePause(1_000));
    try std.testing.expectEqual(Termination.running, ledger.termination);
}

test "the transaction list is bounded and counts what it could not hold" {
    var ledger = Ledger{};
    var index: usize = 0;
    while (index < max_transactions) : (index += 1) {
        const transaction = ledger.begin(.diagnostic_hold, index).?;
        transaction.note(.pause_completed, index);
        transaction.note(.resume_completed, index + 1);
    }
    try std.testing.expect(ledger.begin(.diagnostic_hold, 999) == null);
    try std.testing.expectEqual(@as(u64, 1), ledger.dropped);
    try std.testing.expectEqual(@as(u64, 1), ledger.defectCount());
    try std.testing.expectEqual(max_transactions, ledger.retained().len);
}

test "every stage, cause and termination states its own vocabulary" {
    inline for (@typeInfo(Stage).@"enum".fields) |field| {
        const stage: Stage = @enumFromInt(field.value);
        try std.testing.expect(stage.label().len != 0);
    }
    inline for (@typeInfo(Cause).@"enum".fields) |field| {
        const cause: Cause = @enumFromInt(field.value);
        try std.testing.expect(cause.label().len != 0);
    }
    inline for (@typeInfo(Termination).@"enum".fields) |field| {
        const how: Termination = @enumFromInt(field.value);
        try std.testing.expect(how.label().len != 0);
        try std.testing.expect(how.describe().len != 0);
    }
}

// The 2026-09-01 run: one `GPU PRODUCER PAUSED` line early, no transaction
// behind it, and the guest then executed for another six billion steps. The
// standing stayed `UNRECONCILED` the whole way, which disqualified every wait
// finding in the run on the strength of a claim nothing could check.
test "a pause claim the guest outlived is refuted rather than left standing" {
    var ledger = Ledger{};
    ledger.observeGuestProgress(.guest_code_translated, 412, 20_000_000);
    ledger.observePauseReport(26_000_000);

    // Before any later progress the claim stands: an unmatched report is a
    // real finding until something disproves it.
    try std.testing.expectEqual(Standing.unreconciled, ledger.standing());
    try std.testing.expect(!ledger.standing().guestCausalityIntact());

    // A translation of a guest function the title had never reached before.
    ledger.observeGuestProgress(.guest_code_translated, 1976, 6_118_189_898);

    const standing = ledger.standing();
    try std.testing.expectEqual(Standing.report_refuted, standing);
    try std.testing.expect(standing.guestCausalityIntact());
    // Still a defect, and now one with an owner that is not the guest.
    try std.testing.expect(standing.isDefect());
    try std.testing.expect(std.mem.indexOf(u8, standing.owner(), "printed the pause report") != null);
    try std.testing.expectEqual(ProgressAxis.guest_code_translated, ledger.refuted_by.?);
    try std.testing.expectEqual(@as(u64, 1976 - 412), ledger.refutation_margin);
    try std.testing.expectEqual(@as(u64, 6_118_189_898), ledger.refuted_step);
}

// Progress from before the report proves nothing: the claim is about what
// happened after it.
test "progress that predates the report does not refute it" {
    var ledger = Ledger{};
    ledger.observeGuestProgress(.guest_wait_released, 800, 1_000);
    ledger.observePauseReport(2_000);
    // A resend of an older reading, and a reading at the report's own step.
    ledger.observeGuestProgress(.guest_wait_released, 700, 3_000);
    ledger.observeGuestProgress(.guest_wait_released, 900, 2_000);
    try std.testing.expectEqual(Standing.unreconciled, ledger.standing());
    try std.testing.expect(ledger.refuted_by == null);

    // Strictly after, and strictly higher.
    ledger.observeGuestProgress(.guest_wait_released, 901, 2_001);
    try std.testing.expectEqual(Standing.report_refuted, ledger.standing());
}

// A second report reopens the question. Carrying the old refutation forward
// would let one disproved claim launder every later one.
test "a new pause report is judged on its own evidence" {
    var ledger = Ledger{};
    ledger.observePauseReport(1_000);
    ledger.observeGuestProgress(.guest_export_entered, 5, 2_000);
    try std.testing.expectEqual(Standing.report_refuted, ledger.standing());

    ledger.observePauseReport(3_000);
    try std.testing.expectEqual(Standing.unreconciled, ledger.standing());
    try std.testing.expect(ledger.refuted_by == null);
    try std.testing.expectEqual(@as(u64, 2), ledger.unmatched_reports);

    ledger.observeGuestProgress(.guest_export_entered, 6, 4_000);
    try std.testing.expectEqual(Standing.report_refuted, ledger.standing());
    try std.testing.expectEqual(@as(u64, 1), ledger.refutation_margin);
}

// The refutation is judged against the axis that moved furthest, so the report
// is answered by the strongest evidence rather than the first to arrive.
test "the strongest axis decides the refutation" {
    var ledger = Ledger{};
    ledger.observePauseReport(100);
    ledger.observeGuestProgress(.guest_wait_released, 3, 200);
    try std.testing.expectEqual(ProgressAxis.guest_wait_released, ledger.refuted_by.?);
    ledger.observeGuestProgress(.guest_symbol_reached, 900, 300);
    try std.testing.expectEqual(ProgressAxis.guest_symbol_reached, ledger.refuted_by.?);
    try std.testing.expectEqual(@as(u64, 900), ledger.refutation_margin);
    // A weaker later axis does not take the verdict back.
    ledger.observeGuestProgress(.guest_code_translated, 2, 400);
    try std.testing.expectEqual(ProgressAxis.guest_symbol_reached, ledger.refuted_by.?);
}

// Every axis has to state why a stopped guest cannot move it, or the
// refutation is an assertion rather than an argument.
test "every progress axis explains why a paused guest cannot advance it" {
    inline for (@typeInfo(ProgressAxis).@"enum".fields) |field| {
        const axis: ProgressAxis = @enumFromInt(field.value);
        try std.testing.expect(axis.label().len != 0);
        try std.testing.expect(std.mem.indexOf(u8, axis.whyPausedGuestCannotAdvanceIt(), "executing") != null);
    }
    try std.testing.expectEqual(@as(usize, 4), progress_axis_count);
}
