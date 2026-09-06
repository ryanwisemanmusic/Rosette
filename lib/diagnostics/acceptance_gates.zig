//! A finite definition of "the title is on screen", and a table that maps a
//! symptom to the first owner worth asking.
//!
//! Why this exists
//! ---------------
//! "The window is visible" is not a gate. It was satisfied on 2026-08-31 by a
//! run that rendered none of the title, and it will be satisfied by every
//! future run whether or not anything improves. A gate has to be strict enough
//! that passing it means something and ordered enough that failing one says
//! where to look.
//!
//! So the gates run G0 to G8 in dependency order, and a gate whose predecessor
//! has not passed is `not_reached` rather than failed. That distinction is the
//! whole value: a run that fails G6 has a swap problem, and a run that reports
//! G6 failing because G2 never passed has a ring problem being described in
//! the wrong vocabulary.
//!
//! The classification table is the same idea applied to symptoms. Every row
//! names what to inspect first *and* the conclusion the symptom invites and
//! does not support, because the wrong conclusion is usually more available
//! than the right one.

const std = @import("std");

/// The gates, in the order a run has to pass them.
pub const Gate = enum(u8) {
    /// Reproducible run manifest: identity, config, no unclassified storage or
    /// import fallback on the chain, journal intact.
    reproducible_manifest = 0,
    /// Host and guest substrate: window, memory map, scheduler, sync registry,
    /// provenance, observers within budget.
    substrate = 1,
    /// Authentic GPU bootstrap: engines, callback, ring, write-back, two
    /// canonical publications.
    gpu_bootstrap = 2,
    /// Authoritative PM4: independently implemented structural and stateful
    /// decoders agree, no required unknown opcode, no unexplained truncation.
    authoritative_pm4 = 3,
    /// Real Xenos target activity: state, cache update, EDRAM change, resolve,
    /// checksum change.
    target_activity = 4,
    /// Guest synchronization and progress: the post-draw event has a named
    /// notifier, the signal and callback effect are observed, progress
    /// continues.
    guest_progress = 5,
    /// Authentic swap: VdSwap entered, arguments valid, packet published and
    /// consumed, no host kick required.
    authentic_swap = 6,
    /// Guest frame custody: source discovered, content changed, imported,
    /// presented under the same generation.
    frame_custody = 7,
    /// Stable output: ten consecutive authentic frames, no critical journal
    /// drops, no unexplained disagreement, throughput within budget.
    stable_output = 8,

    pub fn label(self: Gate) []const u8 {
        return switch (self) {
            .reproducible_manifest => "G0 reproducible manifest",
            .substrate => "G1 host and guest substrate",
            .gpu_bootstrap => "G2 authentic GPU bootstrap",
            .authoritative_pm4 => "G3 authoritative PM4",
            .target_activity => "G4 real Xenos target activity",
            .guest_progress => "G5 guest synchronization and progress",
            .authentic_swap => "G6 authentic swap",
            .frame_custody => "G7 guest frame custody",
            .stable_output => "G8 stable output",
        };
    }

    pub fn owner(self: Gate) []const u8 {
        return switch (self) {
            .reproducible_manifest, .substrate => "rosette:harness",
            .gpu_bootstrap, .guest_progress, .authentic_swap => "guest:title",
            .authoritative_pm4, .target_activity => "emulator:gpu",
            .frame_custody => "xenia:presenter",
            .stable_output => "rosette:harness",
        };
    }

    pub fn predecessor(self: Gate) ?Gate {
        return switch (self) {
            .reproducible_manifest => null,
            .substrate => .reproducible_manifest,
            .gpu_bootstrap => .substrate,
            .authoritative_pm4 => .gpu_bootstrap,
            .target_activity => .authoritative_pm4,
            .guest_progress => .target_activity,
            .authentic_swap => .guest_progress,
            .frame_custody => .authentic_swap,
            .stable_output => .frame_custody,
        };
    }

    pub fn describe(self: Gate) []const u8 {
        return switch (self) {
            .reproducible_manifest => "the run states what it is and nothing on the graphics chain fell back unclassified. Without this, two runs cannot be compared and no absence is a fact",
            .substrate => "the host surface, the guest memory map, the scheduler and the observers are all in a state where their measurements mean something",
            .gpu_bootstrap => "the title drove its own GPU bring-up and published at least twice, with each publication applied, drained and reported back to it",
            .authoritative_pm4 => "whether two independently implemented decoders of the same batch agree; only then is an absence in the command stream an absence in what the title asked for",
            .target_activity => "a draw or a controlled vector programmed a target, changed it, resolved it, and changed a checksum the guest can read",
            .guest_progress => "the event the title waits on after a draw has a named notifier that ran, and the title continued",
            .authentic_swap => "the title asked to present, the packet was published and consumed, and no host kick was needed to make it happen",
            .frame_custody => "the guest's own image reached the screen under one generation from discovery to present",
            .stable_output => "the run keeps producing the title's frames at a rate it can sustain, with nothing synthetic counted among them",
        };
    }
};

pub const gate_count: usize = @typeInfo(Gate).@"enum".fields.len;

pub const Outcome = enum(u8) {
    /// Its predecessor has not passed, so this has not been judged.
    not_reached,
    /// Judged and passing.
    passed,
    /// Judged and failing.
    failed,
    /// Reached, and the evidence needed to judge it is missing. Distinct from
    /// failing: the work is to observe, not to fix.
    unevaluable,

    pub fn label(self: Outcome) []const u8 {
        return switch (self) {
            .not_reached => "not-reached",
            .passed => "passed",
            .failed => "FAILED",
            .unevaluable => "UNEVALUABLE",
        };
    }

    pub fn describe(self: Outcome) []const u8 {
        return switch (self) {
            .not_reached => "an earlier gate has not passed, so this one has not been judged. Its zero describes the order and not this gate",
            .passed => "judged against its evidence and passing",
            .failed => "judged against its evidence and failing. This gate's owner is the one to ask",
            .unevaluable => "reached, and the evidence needed to judge it is missing. The work here is to observe, not to fix — and reporting it as a failure would send someone to fix something nobody has measured",
        };
    }
};

/// Why a gate has the outcome it has.
///
/// The board used to carry a bare `detail: u64` next to each row. A reader who
/// found `G1 FAILED detail=8` had a number, and the eight things it counted
/// were only recoverable by reading the code that produced it — so the row that
/// exists to say *where the run is* said less than the reports below it. This
/// is the same fact with its name attached.
///
/// Deliberately one flat list rather than a per-gate union: a reader arrives
/// with a reason and wants to know which gate owns it, and a flat enum makes
/// that a lookup instead of a search.
pub const Reason = enum(u8) {
    /// No reason was supplied. A row in this state is a wiring gap, not a
    /// verdict, and is reported as such rather than defaulting to something
    /// plausible.
    unspecified,
    /// The gate's own evidence is complete and passing.
    satisfied,
    /// An earlier gate has not passed, so this one was never judged.
    predecessor_not_passed,

    // G0 reproducible manifest
    manifest_unsealed,
    manifest_tampered,
    durable_journal_unavailable,
    journal_empty,
    storage_short_read_on_chain,
    journal_channel_lost,

    // G1 host and guest substrate
    substrate_awaiting_first_use,
    substrate_component_broken,
    observers_over_budget,

    // G2 authentic GPU bootstrap
    ring_never_initialized,
    ring_publication_incomplete,

    // G3 authoritative PM4
    pm4_unobserved,
    pm4_live_execution_unobserved,
    pm4_single_account,
    pm4_accounts_uncomparable,
    pm4_decoders_disagree,
    pm4_semantic_defect,

    // G4 real Xenos target activity
    target_output_unjudgeable,
    target_no_output_bearing_draw,

    // G5 guest synchronization and progress
    producer_unobserved,
    producer_waiting_on_missing_notifier,
    producer_quiet_without_a_reason,
    producer_suspended_by_pause,

    // G6 authentic swap
    swap_never_requested,

    // G7 guest frame custody
    custody_no_candidate,
    custody_diagnostic_only,
    custody_blocked,
    custody_lost,

    // G8 stable output
    output_not_stable,

    pub fn label(self: Reason) []const u8 {
        return switch (self) {
            .unspecified => "unspecified",
            .satisfied => "satisfied",
            .predecessor_not_passed => "predecessor-not-passed",
            .manifest_unsealed => "manifest-unsealed",
            .manifest_tampered => "manifest-tampered",
            .durable_journal_unavailable => "durable-journal-unavailable",
            .journal_empty => "journal-empty",
            .storage_short_read_on_chain => "storage-short-read-on-chain",
            .journal_channel_lost => "journal-critical-channel-lost",
            .substrate_awaiting_first_use => "substrate-awaiting-first-use",
            .substrate_component_broken => "substrate-component-broken",
            .observers_over_budget => "observers-over-budget",
            .ring_never_initialized => "ring-never-initialized",
            .ring_publication_incomplete => "ring-publication-incomplete",
            .pm4_unobserved => "pm4-unobserved",
            .pm4_live_execution_unobserved => "pm4-live-execution-unobserved",
            .pm4_single_account => "pm4-single-account",
            .pm4_accounts_uncomparable => "pm4-accounts-uncomparable",
            .pm4_decoders_disagree => "pm4-decoders-disagree",
            .pm4_semantic_defect => "pm4-semantic-defect",
            .target_output_unjudgeable => "target-output-unjudgeable",
            .target_no_output_bearing_draw => "target-no-output-bearing-draw",
            .producer_unobserved => "producer-unobserved",
            .producer_waiting_on_missing_notifier => "producer-waiting-on-missing-notifier",
            .producer_quiet_without_a_reason => "producer-quiet-without-a-reason",
            .producer_suspended_by_pause => "producer-suspended-by-pause",
            .swap_never_requested => "swap-never-requested",
            .custody_no_candidate => "custody-no-candidate",
            .custody_diagnostic_only => "custody-diagnostic-only",
            .custody_blocked => "custody-blocked",
            .custody_lost => "custody-lost",
            .output_not_stable => "output-not-stable",
        };
    }

    /// The sentence a reader needs next. Where a reason is an observation hole
    /// rather than a defect, this says so, because the two send someone to
    /// completely different work.
    pub fn describe(self: Reason) []const u8 {
        return switch (self) {
            .unspecified => "no reason was recorded for this row. That is a gap in the wiring, not a statement about the run",
            .satisfied => "the gate's evidence is complete and passing",
            .predecessor_not_passed => "an earlier gate has not passed. This row's zero describes the order and not this gate",
            .manifest_unsealed => "the run has not stated what it is, so no two runs can be compared and no absence here is a fact",
            .manifest_tampered => "the sealed run identity changed after sealing, so the evidence is not attributable to the run that opened it",
            .durable_journal_unavailable => "the append-only structured evidence sink could not be opened or accepted a record, so a killed run would not have an authoritative prefix",
            .journal_empty => "the journal holds nothing, so there is no record to judge the manifest against",
            .storage_short_read_on_chain => "something on the graphics chain read fewer bytes than it asked for. Any graphics state derived from it is unsound",
            .journal_channel_lost => "a critical journal channel dropped records, so the event order below is incomplete",
            .substrate_awaiting_first_use => "a substrate component is unproven because nothing has exercised it yet. Nothing is broken; the guest has not reached it. The proof for these arrives with the guest's own first use, and the ones Rosette could have proven early are named beside it",
            .substrate_component_broken => "a substrate component was exercised and does not work. Everything downstream of it is a consequence and none of the consequences is worth investigating first",
            .observers_over_budget => "the observers are consuming enough of the run that their own measurements distort what they measure",
            .ring_never_initialized => "the title never initialized a ring buffer, so there is no transport for it to publish into",
            .ring_publication_incomplete => "the ring exists and the two canonical publications have not both been applied, drained and reported back",
            .pm4_live_execution_unobserved => "decoders agree on a retained batch, but no authenticated live executor account proves that the title executed it",
            .pm4_unobserved => "no decoder has read the command stream, so its emptiness is unmeasured rather than empty",
            .pm4_single_account => "only one decoder has an account of the batch, so an absence in the stream cannot be separated from a hole in the decoder that read it. This is an observation gap and the work is to wire the second account, not to change the command stream",
            .pm4_accounts_uncomparable => "two accounts exist and describe different batches, so they cannot corroborate each other",
            .pm4_decoders_disagree => "two decoders read the same batch and disagree. One of them is wrong and neither reading may be built on",
            .pm4_semantic_defect => "a required opcode was decoded as unknown or a packet was truncated with no explanation",
            .target_output_unjudgeable => "no draw has reached the point where a target would be programmed, so there is nothing to judge the target against yet",
            .target_no_output_bearing_draw => "draws reached the target stage and none of them can produce output. The reason is in what the title programmed, not in the count",
            .producer_unobserved => "no progress axis has been read, so the producer's quiet is unmeasured",
            .producer_waiting_on_missing_notifier => "the producer is waiting on an object nothing has ever signalled",
            .producer_quiet_without_a_reason => "the producer has not advanced and no other axis explains why",
            .producer_suspended_by_pause => "a pause was reported and no fault transaction accounts for it, so no wait after it may be read as the guest's own behaviour",
            .swap_never_requested => "the title never asked to present",
            .custody_no_candidate => "no frame has been offered, so custody has nothing to judge",
            .custody_diagnostic_only => "every frame offered came from the harness. A present count from this state is not progress toward an authentic frame",
            .custody_blocked => "an authentic frame existed and could not be taken into custody",
            .custody_lost => "an authentic frame was taken into custody and did not reach the screen",
            .output_not_stable => "the run has not produced a sustained sequence of the title's own frames",
        };
    }

    /// Who to ask, when the reason knows better than the gate's static owner.
    ///
    /// A gate can be owned by one party and blocked by another. `G1` is
    /// Rosette's gate, and a substrate component that is unproven only because
    /// the guest has not reached it is not Rosette's to close — reporting it as
    /// `owner=rosette:harness` sends the next hour to the wrong place, which is
    /// exactly what it did.
    pub fn owner(self: Reason) ?[]const u8 {
        return switch (self) {
            .substrate_awaiting_first_use => "guest:title",
            .substrate_component_broken, .observers_over_budget => "rosette:harness",
            .pm4_unobserved, .pm4_live_execution_unobserved, .pm4_single_account => "rosette:observer",
            .producer_unobserved => "rosette:observer",
            else => null,
        };
    }

    /// Whether the reason is a hole in what Rosette looked at rather than a
    /// fact about the emulator or the title. A frontier in this state is not
    /// work for the gate's owner: it is work for whoever wires the observer.
    pub fn observerHole(self: Reason) bool {
        return switch (self) {
            .pm4_unobserved,
            .pm4_live_execution_unobserved,
            .pm4_single_account,
            .producer_unobserved,
            .target_output_unjudgeable,
            .custody_no_candidate,
            .unspecified,
            => true,
            else => false,
        };
    }
};

pub const reason_count: usize = @typeInfo(Reason).@"enum".fields.len;

/// One gate's state.
pub const Record = struct {
    gate: Gate,
    outcome: Outcome = .not_reached,
    /// Why it has that outcome, by name.
    reason: Reason = .unspecified,
    /// A magnitude belonging to the reason: how many components, how many
    /// frames, which enum value. Only ever read alongside `reason`.
    detail: u64 = 0,
    step: u64 = 0,
};

pub const Summary = struct {
    passed: usize = 0,
    failed: usize = 0,
    unevaluable: usize = 0,
    not_reached: usize = 0,
    /// The first gate that is not passing. Where the run actually is.
    frontier: ?Gate = null,
    frontier_outcome: Outcome = .not_reached,
    frontier_reason: Reason = .unspecified,
    /// Rows whose reason is a hole in the observation rather than a fact about
    /// the run. Non-zero means at least one zero on the board is Rosette's.
    observer_holes: usize = 0,
    /// Rows carrying no reason at all. Non-zero is a wiring gap in the board
    /// itself, and it has to be visible or the board silently degrades back to
    /// the bare number it replaced.
    unattributed: usize = 0,

    /// How far the run got, as a gate count.
    pub fn depth(self: Summary) usize {
        return self.passed;
    }

    /// Who the frontier is actually work for. The gate's static owner, unless
    /// the reason names someone better placed to close it.
    pub fn frontierOwner(self: Summary) []const u8 {
        const gate = self.frontier orelse return "-";
        return self.frontier_reason.owner() orelse gate.owner();
    }
};

pub const Board = struct {
    records: [gate_count]Record = blk: {
        var table: [gate_count]Record = undefined;
        for (&table, 0..) |*slot, index| {
            slot.* = .{ .gate = @enumFromInt(index) };
        }
        break :blk table;
    },

    pub fn passed(self: *const Board, gate: Gate) bool {
        return self.records[@intFromEnum(gate)].outcome == .passed;
    }

    pub fn reachable(self: *const Board, gate: Gate) bool {
        const before = gate.predecessor() orelse return true;
        return self.passed(before);
    }

    /// Judge one gate. A gate whose predecessor has not passed is recorded as
    /// `not_reached` whatever its own evidence says: judging it would produce
    /// a verdict in the wrong vocabulary.
    pub fn judge(
        self: *Board,
        gate: Gate,
        outcome: Outcome,
        reason: Reason,
        detail: u64,
        step: u64,
    ) Outcome {
        const slot = &self.records[@intFromEnum(gate)];
        slot.detail = detail;
        slot.step = step;
        const reached = self.reachable(gate);
        slot.outcome = if (reached) outcome else .not_reached;
        // A gate that was never judged must not keep the caller's reason: it
        // would read as a verdict on evidence nobody looked at.
        slot.reason = if (reached) reason else .predecessor_not_passed;
        return slot.outcome;
    }

    /// The nearest gate before this one that has not passed, which is what
    /// actually stopped it. A row that only says `not-reached` leaves a reader
    /// to walk the chain themselves, and the chain is the point.
    pub fn blockedBy(self: *const Board, gate: Gate) ?Gate {
        var walk = gate.predecessor();
        var found: ?Gate = null;
        while (walk) |before| : (walk = before.predecessor()) {
            if (!self.passed(before)) found = before;
        }
        return found;
    }

    pub fn record(self: *const Board, gate: Gate) Record {
        return self.records[@intFromEnum(gate)];
    }

    pub fn summary(self: *const Board) Summary {
        var out = Summary{};
        for (self.records) |item| {
            switch (item.outcome) {
                .passed => out.passed += 1,
                .failed => out.failed += 1,
                .unevaluable => out.unevaluable += 1,
                .not_reached => out.not_reached += 1,
            }
            if (item.reason == .unspecified) out.unattributed += 1;
            if (item.outcome != .passed and
                item.outcome != .not_reached and
                item.reason.observerHole()) out.observer_holes += 1;
            if (out.frontier == null and item.outcome != .passed) {
                out.frontier = item.gate;
                out.frontier_outcome = item.outcome;
                out.frontier_reason = item.reason;
            }
        }
        return out;
    }

    /// A stable digest of the board's *shape*, so a renderer can tell a run
    /// that moved from one that is repeating itself. The reason is part of the
    /// shape: a gate that changed why it is failing has changed, even when the
    /// outcome column did not move.
    pub fn fingerprint(self: *const Board) u64 {
        var hash: u64 = 0;
        for (self.records) |item| {
            hash = hash *% 31 +% @intFromEnum(item.outcome);
            hash = hash *% 31 +% @intFromEnum(item.reason);
        }
        return hash;
    }
};

/// The symptoms a reader arrives with, the owner to ask first, and the
/// conclusion the symptom invites and does not support.
pub const Symptom = enum(u8) {
    window_shows_diagnostic_frames = 0,
    vdswap_never_entered = 1,
    ring_initialized_no_write_pointer = 2,
    pointer_printed_not_applied = 3,
    pm4_consumed_no_target_state = 4,
    draws_all_no_output = 5,
    target_changes_no_guest_frame = 6,
    callback_registered_wait_times_out = 7,
    many_never_notified_objects = 8,
    pause_without_fault_transaction = 9,
    final_signal_at_jit_symbol = 10,
    short_read_or_mmap_fallback = 11,
    high_hit_rate_low_guest_rate = 12,
    decoders_disagree = 13,
    substrate_gate_failed_before_the_guest_ran = 14,
    degraded_host_page_at_the_top_of_the_log = 15,
    starved_stage_with_no_named_cause = 16,

    pub fn label(self: Symptom) []const u8 {
        return switch (self) {
            .window_shows_diagnostic_frames => "window exists and diagnostic frames present",
            .vdswap_never_entered => "VdSwap never entered",
            .ring_initialized_no_write_pointer => "ring initialized but no write pointer",
            .pointer_printed_not_applied => "pointer printed but not applied",
            .pm4_consumed_no_target_state => "PM4 consumed but no target state",
            .draws_all_no_output => "draws all no-rasterization/no-memexport",
            .target_changes_no_guest_frame => "target changes but no guest frame",
            .callback_registered_wait_times_out => "callback registered but wait times out",
            .many_never_notified_objects => "many never-notified idle objects",
            .pause_without_fault_transaction => "pause warning without fault transaction",
            .final_signal_at_jit_symbol => "final signal at a JIT symbol",
            .short_read_or_mmap_fallback => "short read or mmap fallback",
            .high_hit_rate_low_guest_rate => "99% decode hit rate and very low guest rate",
            .decoders_disagree => "one PM4 report says no truncation and another says four",
            .substrate_gate_failed_before_the_guest_ran => "G1 failed from step zero with owner rosette:harness",
            .degraded_host_page_at_the_top_of_the_log => "a degraded host page granularity at the top of every run",
            .starved_stage_with_no_named_cause => "a stage reported starved with no cause beside it",
        };
    }

    /// Who to ask first.
    pub fn firstOwner(self: Symptom) []const u8 {
        return switch (self) {
            .window_shows_diagnostic_frames => "guest frame source / producer",
            .vdswap_never_entered => "guest producer, kernel video, synchronization, callback effect",
            .ring_initialized_no_write_pointer => "guest MMIO, protection, producer",
            .pointer_printed_not_applied => "ring transport authority",
            .pm4_consumed_no_target_state => "Xenos register, PM4 and render-target path",
            .draws_all_no_output => "shader, rasterization and target path, or an early probe batch",
            .target_changes_no_guest_frame => "resolve, frontbuffer, VdSwap, custody",
            .callback_registered_wait_times_out => "interrupt effect and object identity",
            .many_never_notified_objects => "object classification",
            .pause_without_fault_transaction => "the emulator's pause and fault journal",
            .final_signal_at_jit_symbol => "run-integrity policy",
            .short_read_or_mmap_fallback => "storage and reservation ledger",
            .high_hit_rate_low_guest_rate => "translation cache and JIT budget",
            .decoders_disagree => "parser and report authority",
            .substrate_gate_failed_before_the_guest_ran => "the component readiness ledger's substrate rows, not the harness",
            .degraded_host_page_at_the_top_of_the_log => "the guest page protection fidelity row beside it",
            .starved_stage_with_no_named_cause => "the probe's own call site",
        };
    }

    /// The conclusion the symptom invites and does not support. This is the
    /// half a reader needs and rarely writes down.
    pub fn doNotConclude(self: Symptom) []const u8 {
        return switch (self) {
            .window_shows_diagnostic_frames => "that the presenter is broken",
            .vdswap_never_entered => "that Vulkan or Metal is broken",
            .ring_initialized_no_write_pointer => "that the command processor or presenter is broken",
            .pointer_printed_not_applied => "that the guest never wrote anything",
            .pm4_consumed_no_target_state => "that a draw count means pixels exist",
            .draws_all_no_output => "that the GPU is rendering black",
            .target_changes_no_guest_frame => "that the presenter should synthesise a swap",
            .callback_registered_wait_times_out => "that callback registration is sufficient",
            .many_never_notified_objects => "that the whole emulator is deadlocked",
            .pause_without_fault_transaction => "that the later wait caused the pause",
            .final_signal_at_jit_symbol => "that the guest crashed spontaneously",
            .short_read_or_mmap_fallback => "that the graphics state is valid",
            .high_hit_rate_low_guest_rate => "that the run is performant",
            .decoders_disagree => "that either report can be ignored",
            // Every substrate component but four can only be proven by the
            // guest's own first use. Before the title reaches them the gate is
            // unevaluable, and reading it as a harness failure sent the first
            // 3.3 billion steps of the 2026-09-01 run to the wrong owner.
            .substrate_gate_failed_before_the_guest_ran => "that the harness is broken, or that anything downstream is not-reached for a reason worth fixing",
            // A host page four times the console's is a property of the
            // machine. It only becomes a finding when nothing restores the
            // resolution, which is a separate measurement.
            .degraded_host_page_at_the_top_of_the_log => "that guest page protection is coarse, or that any timing symptom below it is explained",
            // Starved means the observer produced nothing. Without a cause it
            // names no work at all, and the absent cause is Rosette's.
            .starved_stage_with_no_named_cause => "that the stage is absent in the title, or that the probe is broken",
        };
    }

    /// The gate this symptom belongs to, so a reader arriving with a symptom
    /// lands in the same order the gates run in.
    pub fn gate(self: Symptom) Gate {
        return switch (self) {
            .short_read_or_mmap_fallback => .reproducible_manifest,
            .high_hit_rate_low_guest_rate, .final_signal_at_jit_symbol => .substrate,
            .ring_initialized_no_write_pointer, .pointer_printed_not_applied => .gpu_bootstrap,
            .decoders_disagree => .authoritative_pm4,
            .pm4_consumed_no_target_state, .draws_all_no_output => .target_activity,
            .callback_registered_wait_times_out,
            .many_never_notified_objects,
            .pause_without_fault_transaction,
            => .guest_progress,
            .vdswap_never_entered => .authentic_swap,
            .target_changes_no_guest_frame, .window_shows_diagnostic_frames => .frame_custody,
            .substrate_gate_failed_before_the_guest_ran,
            .degraded_host_page_at_the_top_of_the_log,
            => .substrate,
            .starved_stage_with_no_named_cause => .authentic_swap,
        };
    }
};

pub const symptom_count: usize = @typeInfo(Symptom).@"enum".fields.len;

test "a gate whose predecessor failed is not reached rather than failed" {
    var board = Board{};
    _ = board.judge(.reproducible_manifest, .failed, .storage_short_read_on_chain, 1, 100);
    // Judging a later gate with passing evidence still records not-reached:
    // its verdict would be in the wrong vocabulary.
    try std.testing.expectEqual(
        Outcome.not_reached,
        board.judge(.authentic_swap, .passed, .satisfied, 0, 200),
    );
    // And the reason it keeps is the ordering, never the caller's.
    try std.testing.expectEqual(Reason.predecessor_not_passed, board.record(.authentic_swap).reason);
    try std.testing.expect(!board.passed(.authentic_swap));
    try std.testing.expect(!board.reachable(.substrate));

    const totals = board.summary();
    try std.testing.expectEqual(Gate.reproducible_manifest, totals.frontier.?);
    try std.testing.expectEqual(Outcome.failed, totals.frontier_outcome);
    try std.testing.expectEqual(@as(usize, 0), totals.depth());
}

// The 2026-08-31 run's actual position: substrate and bootstrap fine, target
// activity never reached.
test "the frontier names where the run is rather than the loudest symptom" {
    var board = Board{};
    _ = board.judge(.reproducible_manifest, .passed, .satisfied, 0, 10);
    _ = board.judge(.substrate, .passed, .satisfied, 0, 20);
    _ = board.judge(.gpu_bootstrap, .passed, .satisfied, 0, 30);
    _ = board.judge(.authoritative_pm4, .passed, .satisfied, 0, 40);
    _ = board.judge(.target_activity, .failed, .target_no_output_bearing_draw, 24, 50);
    _ = board.judge(.guest_progress, .failed, .producer_quiet_without_a_reason, 112, 60);

    const totals = board.summary();
    try std.testing.expectEqual(@as(usize, 4), totals.depth());
    try std.testing.expectEqual(Gate.target_activity, totals.frontier.?);
    try std.testing.expectEqualStrings("emulator:gpu", Gate.target_activity.owner());
    // Everything past the frontier is not reached, not failed.
    try std.testing.expectEqual(Outcome.not_reached, board.record(.guest_progress).outcome);
    try std.testing.expectEqual(Outcome.not_reached, board.record(.stable_output).outcome);
}

test "unevaluable is distinct from failed and says the work is to observe" {
    var board = Board{};
    _ = board.judge(.reproducible_manifest, .unevaluable, .journal_empty, 0, 10);
    try std.testing.expectEqual(Outcome.unevaluable, board.record(.reproducible_manifest).outcome);
    try std.testing.expectEqual(@as(usize, 1), board.summary().unevaluable);
    try std.testing.expect(std.mem.indexOf(u8, Outcome.unevaluable.describe(), "nobody has measured") != null);
    // Still not passed, so nothing downstream is reachable.
    try std.testing.expect(!board.reachable(.substrate));
}

test "the whole board passing is the definition of the title being on screen" {
    var board = Board{};
    inline for (@typeInfo(Gate).@"enum".fields) |field| {
        _ = board.judge(@enumFromInt(field.value), .passed, .satisfied, 0, 100 + field.value);
    }
    const totals = board.summary();
    try std.testing.expectEqual(gate_count, totals.depth());
    try std.testing.expect(totals.frontier == null);
    try std.testing.expectEqual(@as(usize, 0), totals.failed);
}

// Every row of the audit's failure classification matrix.
test "every symptom names an owner, a refused conclusion and a gate" {
    inline for (@typeInfo(Symptom).@"enum".fields) |field| {
        const symptom: Symptom = @enumFromInt(field.value);
        try std.testing.expect(symptom.label().len != 0);
        try std.testing.expect(symptom.firstOwner().len != 0);
        try std.testing.expect(symptom.doNotConclude().len != 0);
        try std.testing.expect(symptom.gate().label().len != 0);
    }
    try std.testing.expectEqual(@as(usize, 17), symptom_count);
}

test "the symptoms that misled this investigation map to the right gates" {
    // A visible window with diagnostic frames is a custody question, not a
    // presenter defect.
    try std.testing.expectEqual(Gate.frame_custody, Symptom.window_shows_diagnostic_frames.gate());
    try std.testing.expect(std.mem.indexOf(u8, Symptom.window_shows_diagnostic_frames.doNotConclude(), "presenter is broken") != null);

    // A final SIGSEGV at a JIT symbol is a policy decision at the substrate
    // gate, not a guest crash.
    try std.testing.expectEqual(Gate.substrate, Symptom.final_signal_at_jit_symbol.gate());
    try std.testing.expect(std.mem.indexOf(u8, Symptom.final_signal_at_jit_symbol.doNotConclude(), "spontaneously") != null);

    // A pause with no fault transaction is a guest-progress question and the
    // later wait is not its cause.
    try std.testing.expectEqual(Gate.guest_progress, Symptom.pause_without_fault_transaction.gate());
    try std.testing.expect(std.mem.indexOf(u8, Symptom.pause_without_fault_transaction.doNotConclude(), "caused the pause") != null);
}

test "the gate order runs from the manifest to stable output with no cycle" {
    try std.testing.expect(Gate.reproducible_manifest.predecessor() == null);
    var gate: Gate = .stable_output;
    var steps: usize = 0;
    while (gate.predecessor()) |before| {
        gate = before;
        steps += 1;
        try std.testing.expect(steps < gate_count + 1);
    }
    try std.testing.expectEqual(Gate.reproducible_manifest, gate);
    try std.testing.expectEqual(gate_count - 1, steps);

    inline for (@typeInfo(Gate).@"enum".fields) |field| {
        const which: Gate = @enumFromInt(field.value);
        try std.testing.expect(which.label().len != 0);
        try std.testing.expect(which.owner().len != 0);
        try std.testing.expect(which.describe().len != 0);
    }
}

// The board's job is to say where the run is. A row that says `FAILED
// detail=8` says less than the reports below it, and the eight things it
// counted were only recoverable from the code that produced it.
test "every reason carries a name and a sentence, and the sentences are distinct" {
    var seen_labels: [reason_count][]const u8 = undefined;
    inline for (@typeInfo(Reason).@"enum".fields, 0..) |field, index| {
        const reason: Reason = @enumFromInt(field.value);
        try std.testing.expect(reason.label().len != 0);
        try std.testing.expect(reason.describe().len != 0);
        seen_labels[index] = reason.label();
    }
    for (seen_labels, 0..) |left, i| {
        for (seen_labels[i + 1 ..]) |right| {
            try std.testing.expect(!std.mem.eql(u8, left, right));
        }
    }
}

// The 2026-09-01 run's actual first three billion steps: `G1 FAILED
// owner=rosette:harness`, for a substrate whose remaining components were
// unproven only because the title had not reached them yet. Nothing was
// broken and nothing was Rosette's to fix, and the frontier said otherwise for
// half the run.
test "a substrate awaiting the guest is not a harness failure" {
    var board = Board{};
    _ = board.judge(.reproducible_manifest, .passed, .satisfied, 0, 10);
    _ = board.judge(.substrate, .unevaluable, .substrate_awaiting_first_use, 8, 20);

    const totals = board.summary();
    try std.testing.expectEqual(Gate.substrate, totals.frontier.?);
    try std.testing.expectEqual(Outcome.unevaluable, totals.frontier_outcome);
    try std.testing.expectEqual(Reason.substrate_awaiting_first_use, totals.frontier_reason);
    // The gate is Rosette's; this particular blockage is not.
    try std.testing.expectEqualStrings("rosette:harness", Gate.substrate.owner());
    try std.testing.expectEqualStrings("guest:title", totals.frontierOwner());
    try std.testing.expectEqual(@as(usize, 0), totals.failed);

    // A component that was exercised and does not work is the opposite case,
    // and it does belong to the harness.
    _ = board.judge(.substrate, .failed, .substrate_component_broken, 1, 30);
    const broken = board.summary();
    try std.testing.expectEqual(@as(usize, 1), broken.failed);
    try std.testing.expectEqualStrings("rosette:harness", broken.frontierOwner());
}

// The frontier at step 6.1B: one PM4 account, so the stream's emptiness could
// not be separated from a hole in the only decoder that read it. That is work
// for whoever wires the second account, not for the GPU.
test "an observation hole at the frontier is named as one" {
    var board = Board{};
    _ = board.judge(.reproducible_manifest, .passed, .satisfied, 0, 10);
    _ = board.judge(.substrate, .passed, .satisfied, 0, 20);
    _ = board.judge(.gpu_bootstrap, .passed, .satisfied, 2, 30);
    _ = board.judge(.authoritative_pm4, .unevaluable, .pm4_single_account, 1, 40);
    _ = board.judge(.target_activity, .unevaluable, .target_output_unjudgeable, 0, 40);

    const totals = board.summary();
    try std.testing.expectEqual(@as(usize, 3), totals.depth());
    try std.testing.expectEqual(Gate.authoritative_pm4, totals.frontier.?);
    try std.testing.expectEqual(Reason.pm4_single_account, totals.frontier_reason);
    try std.testing.expect(totals.frontier_reason.observerHole());
    try std.testing.expectEqualStrings("rosette:observer", totals.frontierOwner());
    // The gate's static owner would have sent the reader to the GPU.
    try std.testing.expectEqualStrings("emulator:gpu", Gate.authoritative_pm4.owner());
    // Only the judged rows count as holes; the not-reached ones downstream
    // describe the order and are not holes in anything.
    try std.testing.expectEqual(@as(usize, 1), totals.observer_holes);
    try std.testing.expect(std.mem.indexOf(u8, Reason.pm4_single_account.describe(), "wire the second account") != null);
}

// `not-reached` is only useful if the row says what stopped it. Walking the
// chain by hand is what the board exists to remove.
test "a not-reached row names the gate that actually stopped it" {
    var board = Board{};
    _ = board.judge(.reproducible_manifest, .passed, .satisfied, 0, 10);
    _ = board.judge(.substrate, .failed, .substrate_component_broken, 1, 20);
    _ = board.judge(.gpu_bootstrap, .passed, .satisfied, 0, 30);
    _ = board.judge(.stable_output, .passed, .satisfied, 0, 40);

    try std.testing.expect(board.blockedBy(.reproducible_manifest) == null);
    try std.testing.expectEqual(Gate.substrate, board.blockedBy(.gpu_bootstrap).?);
    // The furthest-upstream unpassed predecessor, not the nearest one: the
    // nearest is itself only not-reached because of the same gate.
    try std.testing.expectEqual(Gate.substrate, board.blockedBy(.stable_output).?);
    try std.testing.expectEqual(Outcome.not_reached, board.record(.stable_output).outcome);
}

// A board that silently loses its reasons degrades back to the bare number it
// replaced, so the omission has to be countable.
test "a row with no reason is reported rather than defaulted" {
    var board = Board{};
    try std.testing.expectEqual(@as(usize, gate_count), board.summary().unattributed);
    _ = board.judge(.reproducible_manifest, .passed, .satisfied, 0, 10);
    try std.testing.expectEqual(@as(usize, gate_count - 1), board.summary().unattributed);
    try std.testing.expect(Reason.unspecified.observerHole());
}

// The fingerprint drives whether a renderer reprints the board. A gate that
// changed *why* it is failing has changed, and a digest that ignored the
// reason would hide the transition that matters most.
test "the fingerprint moves when only the reason changes" {
    var board = Board{};
    _ = board.judge(.reproducible_manifest, .failed, .journal_empty, 0, 10);
    const before = board.fingerprint();
    _ = board.judge(.reproducible_manifest, .failed, .storage_short_read_on_chain, 0, 20);
    try std.testing.expect(before != board.fingerprint());
}

// The three readings that misled the 2026-09-01 investigation, filed the same
// way as the ones before them: the symptom, who to ask, and the conclusion it
// invites and does not support.
test "the 2026-09-01 symptoms land on the substrate and the swap" {
    try std.testing.expectEqual(
        Gate.substrate,
        Symptom.substrate_gate_failed_before_the_guest_ran.gate(),
    );
    try std.testing.expect(std.mem.indexOf(
        u8,
        Symptom.substrate_gate_failed_before_the_guest_ran.doNotConclude(),
        "harness is broken",
    ) != null);

    try std.testing.expectEqual(
        Gate.substrate,
        Symptom.degraded_host_page_at_the_top_of_the_log.gate(),
    );
    try std.testing.expect(std.mem.indexOf(
        u8,
        Symptom.degraded_host_page_at_the_top_of_the_log.firstOwner(),
        "fidelity row beside it",
    ) != null);

    // A starved stage is a swap-chain reading whose owner is the probe's call
    // site, not the title.
    try std.testing.expectEqual(
        Gate.authentic_swap,
        Symptom.starved_stage_with_no_named_cause.gate(),
    );
    try std.testing.expect(std.mem.indexOf(
        u8,
        Symptom.starved_stage_with_no_named_cause.doNotConclude(),
        "absent in the title",
    ) != null);
}
