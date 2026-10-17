//! Which of several disagreeing statements about the same fact is current.
//!
//! The emulator states the same facts from many code paths, each carrying a
//! snapshot taken at the moment that path ran. Those snapshots are never
//! retracted. A reader — human or machine — greps for a phrase, finds the
//! first line that matches, and reads a value that stopped being true seconds
//! ago. This is not a hypothetical failure mode; it is the dominant one:
//!
//! | claim | one source says | another says |
//! | --- | --- | --- |
//! | ring initialised | `ring_init=NO rb_base=00000000` at 515 ms | `ring_init=YES rb_base=1FC9B000` at 2279 ms |
//! | interrupt callback set | `interrupt_callback_set=NO` at 515–1515 ms | `callback_set=YES` at 2279 ms |
//!
//! Both readings are in the same log. The first is the one that repeats often
//! enough to be found, and it sent two separate investigations after a ring
//! that was in fact configured and a callback that was in fact registered.
//!
//! ## The rule that separates a stale claim from a real disagreement
//!
//! The naive rule — "newest wins" — is not enough, because it cannot tell a
//! snapshot nobody refreshed from two subsystems that genuinely disagree right
//! now. The distinction that works is **whether the losing source kept
//! repeating its claim after being contradicted**:
//!
//!   * A source that stated a value, was contradicted by a newer observation,
//!     and then **stopped emitting** is `superseded`. Its value is a stale
//!     snapshot and must never be reported as current.
//!   * A source that is **still repeating** a value after a contradiction is
//!     `contested`. Two live observers disagree about the present, which is a
//!     defect somewhere and the only case that deserves attention.
//!
//! That rule needs no tuned freshness window and no wall-clock threshold. It
//! asks the only question that matters: is anything still asserting this?
//!
//! This package holds no state and reads no log. It is the vocabulary and the
//! rule; the ledger is `lib/diagnostics/claim_reconciliation.zig`.

const std = @import("std");

/// A fact more than one observer states independently.
///
/// Deliberately a closed enum rather than free-form keys. A claim is worth
/// reconciling only when two named observers are known to report it, and an
/// open key space would silently accept a typo as a new fact nobody
/// contradicts.
pub const Claim = enum(u8) {
    ring_initialised,
    ring_init_acknowledged,
    ring_base_address,
    ring_size_bytes,
    ring_read_pointer,
    ring_write_pointer,
    interrupt_callback_set,
    interrupt_callback_address,
    /// Times Xenia says its PowerPC CPU engine ran the title's graphics
    /// callback. Only Xenia-domain sources may state this claim.
    callback_completions,
    /// Draw completions the modelled Xenos runtime dispatched to a guest
    /// callback in Rosette's x86 harness. Deliberately a different claim from
    /// `callback_completions`: they count different transactions in different
    /// execution domains and comparing their values is an observer defect.
    draw_completion_dispatches,
    swap_packets_consumed,
    guest_main_ready,
    /// Times the title entered `VdQueryVideoMode`, the first call of GPU
    /// bring-up.
    ///
    /// This and the four below exist because two Rosette observers of the same
    /// entry were never compared. On 2026-09-05 the boundary gate reported
    /// `VdQueryVideoMode ... boundary_never_crossed` at step 2.1B while the
    /// guest log carried `DEBUG: VdQueryVideoMode called (count=1)`. An armed
    /// instruction-pointer tracepoint and the emulator's own breadcrumb cannot
    /// both be right, and nothing in the run put them side by side — so the
    /// frontier named a boundary the title had already crossed and the reader
    /// spent the investigation on the wrong end of the pipeline.
    vd_query_video_mode_entries,
    /// Times the title entered `VdInitializeEngines`.
    vd_initialize_engines_entries,
    /// Times the title entered `VdInitializeRingBuffer`.
    vd_initialize_ring_buffer_entries,
    /// Times the title entered `VdSetGraphicsInterruptCallback`.
    vd_set_graphics_interrupt_callback_entries,
    /// Times the title entered `VdSwap`.
    vd_swap_entries,

    pub fn label(self: Claim) []const u8 {
        return switch (self) {
            .ring_initialised => "ring initialised",
            .ring_init_acknowledged => "ring init acknowledged",
            .ring_base_address => "ring base address",
            .ring_size_bytes => "ring size bytes",
            .ring_read_pointer => "ring read pointer",
            .ring_write_pointer => "ring write pointer",
            .interrupt_callback_set => "interrupt callback set",
            .interrupt_callback_address => "interrupt callback address",
            .vd_query_video_mode_entries => "VdQueryVideoMode entries",
            .vd_initialize_engines_entries => "VdInitializeEngines entries",
            .vd_initialize_ring_buffer_entries => "VdInitializeRingBuffer entries",
            .vd_set_graphics_interrupt_callback_entries => "VdSetGraphicsInterruptCallback entries",
            .vd_swap_entries => "VdSwap entries",
            .callback_completions => "emulator callback completions",
            .draw_completion_dispatches => "modelled draw completion dispatches",
            .swap_packets_consumed => "swap packets consumed",
            .guest_main_ready => "guest main ready",
        };
    }

    /// Whether a disagreement on this claim can ever be benign.
    ///
    /// Counters may be reconciled only when their sources count the same event.
    /// Different-domain counters have distinct `Claim` values so they cannot
    /// manufacture a contest merely because their totals differ.
    pub fn isCounter(self: Claim) bool {
        return switch (self) {
            .callback_completions,
            .draw_completion_dispatches,
            .swap_packets_consumed,
            => true,
            else => false,
        };
    }
};

pub const claim_count: usize = @typeInfo(Claim).@"enum".fields.len;

/// Who stated it. Each is one emitter, not one subsystem: the whole point is
/// that a subsystem has several emitters that disagree.
pub const Source = enum(u8) {
    /// `RING BUFFER: no-swap diagnosis stage=... ring_init=... rb_base=...`
    /// Emitted early and repeatedly during bring-up, then abandoned. The
    /// single largest source of stale readings in this system.
    xenia_no_swap_diagnosis,
    /// `DEBUG: gpu_startup_watch ready: ... ring_init=YES init_ack=YES ...`
    /// Emitted once bring-up completes, and therefore the one that carries the
    /// settled truth.
    xenia_startup_watch,
    /// `DEBUG: CALLBACK WATCHDOG: interrupt_callback_set=...`
    xenia_callback_watchdog,
    /// `GPU FALLBACK PROBE INPUTS: ... ring_init=... authentic_wptr=...`
    xenia_fallback_probe,
    /// `RING BUFFER: callback-exec timing ... ring_init=... rb_base=...`
    xenia_callback_exec_timing,
    /// Rosette's own ring publication tracker.
    rosette_ring_publication,
    /// Rosette's modelled Xenos command processor.
    rosette_xenos_runtime,
    /// Rosette's GPU interrupt dispatch counters.
    rosette_interrupt_dispatch,
    /// Rosette's kernel import handlers.
    rosette_kernel_import,
    /// Rosette's armed instruction-pointer tracepoint on a guest export. It
    /// sees every entry to the address it is armed for and nothing at any
    /// other address, so it is exact when the address is right and silent when
    /// it is not — which is precisely why it needs a second observer.
    rosette_boundary_tracepoint,
    /// The emulator's own `DEBUG: <export> called (count=N)` breadcrumb. It
    /// counts entries the emulator itself acknowledged, independent of which
    /// address Rosette armed.
    xenia_export_breadcrumb,

    pub fn label(self: Source) []const u8 {
        return switch (self) {
            .xenia_no_swap_diagnosis => "xenia:no-swap-diagnosis",
            .xenia_startup_watch => "xenia:startup-watch",
            .xenia_callback_watchdog => "xenia:callback-watchdog",
            .xenia_fallback_probe => "xenia:fallback-probe",
            .xenia_callback_exec_timing => "xenia:callback-exec-timing",
            .rosette_ring_publication => "rosette:ring-publication",
            .rosette_xenos_runtime => "rosette:xenos-runtime",
            .rosette_interrupt_dispatch => "rosette:interrupt-dispatch",
            .rosette_kernel_import => "rosette:kernel-import",
            .rosette_boundary_tracepoint => "rosette:boundary-tracepoint",
            .xenia_export_breadcrumb => "xenia:export-breadcrumb",
        };
    }

    /// Which process the observer lives in. A contest that crosses this
    /// boundary is a host/guest model split; one that does not is an internal
    /// inconsistency in a single process, and they need different repairs.
    pub fn side(self: Source) Side {
        return switch (self) {
            .xenia_no_swap_diagnosis,
            .xenia_startup_watch,
            .xenia_callback_watchdog,
            .xenia_fallback_probe,
            .xenia_callback_exec_timing,
            .xenia_export_breadcrumb,
            => .emulator,
            .rosette_ring_publication,
            .rosette_xenos_runtime,
            .rosette_interrupt_dispatch,
            .rosette_kernel_import,
            .rosette_boundary_tracepoint,
            => .harness,
        };
    }

    /// True for an emitter that samples during bring-up and is not refreshed
    /// afterwards. Knowing this in advance is not the reconciliation rule —
    /// the rule is behavioural — but it lets a report say *why* a source went
    /// quiet instead of only that it did.
    pub fn isBringupSnapshot(self: Source) bool {
        return switch (self) {
            .xenia_no_swap_diagnosis,
            .xenia_callback_watchdog,
            .xenia_callback_exec_timing,
            => true,
            else => false,
        };
    }
};

pub const source_count: usize = @typeInfo(Source).@"enum".fields.len;

pub const Side = enum(u8) {
    emulator,
    harness,

    pub fn label(self: Side) []const u8 {
        return switch (self) {
            .emulator => "emulator",
            .harness => "harness",
        };
    }
};

/// How the observers of one claim stand relative to each other.
pub const Agreement = enum(u8) {
    /// Nobody has stated it.
    unobserved,
    /// One observer has stated it. True as far as it goes, and unverified.
    single_source,
    /// Every observer that has stated it agrees.
    agreed,
    /// Observers disagreed, and every losing source stopped emitting after
    /// being contradicted. The newest value is current and the older ones are
    /// stale snapshots.
    superseded,
    /// A losing source is still repeating its value after being contradicted.
    /// Two live observers disagree about the present.
    contested,

    pub fn label(self: Agreement) []const u8 {
        return switch (self) {
            .unobserved => "unobserved",
            .single_source => "single-source",
            .agreed => "agreed",
            .superseded => "superseded",
            .contested => "CONTESTED",
        };
    }

    /// True when a reader must not quote the losing value as current.
    pub fn hasStaleReadings(self: Agreement) bool {
        return self == .superseded;
    }

    /// True when the disagreement is a defect rather than a reading trap.
    pub fn isDefect(self: Agreement) bool {
        return self == .contested;
    }

    pub fn guidance(self: Agreement) []const u8 {
        return switch (self) {
            .unobserved => "no observer has stated this; it is unknown rather than false",
            .single_source => "one observer states this and nothing corroborates it; a second source would make it checkable",
            .agreed => "every observer that stated this agrees",
            .superseded => "observers disagreed and the losing sources stopped emitting after being contradicted. The newest value is current; the older ones are stale snapshots that are still present in the log and must not be quoted as the present state",
            .contested => "a source is still repeating a value that a newer observation contradicts. Two live observers disagree about the present: this is a defect, and when the two sit on opposite sides of the host/guest boundary it is a model split rather than a race",
        };
    }
};

/// The reading for one whole ledger.
pub const Finding = enum(u8) {
    /// No claim has more than one observer, so nothing has been cross-checked.
    uncorroborated,
    /// Every multi-source claim agrees.
    consistent,
    /// Stale readings exist. Not a defect, but the log contains values that
    /// will mislead anyone who greps for them.
    stale_readings_present,
    /// Live observers disagree within one process.
    internal_contest,
    /// Live observers disagree across the host/guest boundary. The two models
    /// have diverged and neither report can be read alone.
    model_split,

    pub fn label(self: Finding) []const u8 {
        return switch (self) {
            .uncorroborated => "uncorroborated",
            .consistent => "consistent",
            .stale_readings_present => "stale_readings_present",
            .internal_contest => "internal_contest",
            .model_split => "model_split",
        };
    }

    pub fn guidance(self: Finding) []const u8 {
        return switch (self) {
            .uncorroborated => "no claim has two independent observers, so no cross-check has been performed. Agreement here is absence of evidence",
            .consistent => "every claim with more than one observer agrees; the log's snapshots and the harness's counters describe the same machine",
            .stale_readings_present => "the log contains superseded snapshots whose sources stopped refreshing them. Nothing is broken, but a reader who greps for those phrases reads a value that stopped being true. Quote the current value named below, not the first match in the log",
            .internal_contest => "two observers inside one process disagree about the present state. One of them is reading a field the other does not write",
            .model_split => "the harness and the emulator disagree about the present state of the same object. Their models have diverged: each report is internally consistent and they cannot both be describing the machine that is running",
        };
    }
};

/// The reconciliation rule.
///
/// `loser_repeated_after_contradiction` is the whole rule. A source that went
/// quiet after being contradicted was describing a moment that has passed; one
/// that is still talking is describing a present it disagrees about.
pub fn agreementOf(
    observers: usize,
    values_differ: bool,
    loser_repeated_after_contradiction: bool,
) Agreement {
    if (observers == 0) return .unobserved;
    if (observers == 1) return .single_source;
    if (!values_differ) return .agreed;
    return if (loser_repeated_after_contradiction) .contested else .superseded;
}

pub fn findingOf(
    corroborated_claims: usize,
    superseded_claims: usize,
    contested_claims: usize,
    contest_crosses_sides: bool,
) Finding {
    if (contested_claims != 0) {
        return if (contest_crosses_sides) .model_split else .internal_contest;
    }
    if (superseded_claims != 0) return .stale_readings_present;
    if (corroborated_claims == 0) return .uncorroborated;
    return .consistent;
}

pub fn contractIsWellFormed() bool {
    if (agreementOf(0, false, false) != .unobserved) return false;
    if (agreementOf(1, false, false) != .single_source) return false;
    if (agreementOf(2, false, false) != .agreed) return false;
    // The two cases the whole package exists to separate.
    if (agreementOf(2, true, false) != .superseded) return false;
    if (agreementOf(2, true, true) != .contested) return false;

    if (findingOf(3, 0, 0, false) != .consistent) return false;
    if (findingOf(3, 1, 0, false) != .stale_readings_present) return false;
    if (findingOf(3, 0, 1, false) != .internal_contest) return false;
    if (findingOf(3, 0, 1, true) != .model_split) return false;
    if (findingOf(0, 0, 0, false) != .uncorroborated) return false;

    // A contest outranks a stale reading: a defect must not be hidden behind a
    // reading trap.
    if (findingOf(3, 5, 1, true) != .model_split) return false;

    if (Source.xenia_startup_watch.side() != .emulator) return false;
    if (Source.rosette_xenos_runtime.side() != .harness) return false;
    if (!Source.xenia_no_swap_diagnosis.isBringupSnapshot()) return false;
    if (Source.xenia_startup_watch.isBringupSnapshot()) return false;
    if (!Claim.callback_completions.isCounter()) return false;
    if (Claim.ring_initialised.isCounter()) return false;
    return true;
}

test "a snapshot that stopped refreshing is superseded, not contested" {
    // The live case: `ring_init=NO rb_base=00000000` from the no-swap
    // diagnosis at 515 ms, contradicted by the startup watch at 2279 ms, and
    // never re-emitted. Two investigations were spent on that stale NO.
    try std.testing.expectEqual(Agreement.superseded, agreementOf(2, true, false));
    try std.testing.expect(Agreement.superseded.hasStaleReadings());
    try std.testing.expect(!Agreement.superseded.isDefect());
    try std.testing.expect(std.mem.indexOf(u8, Agreement.superseded.guidance(), "stale snapshots") != null);
}

test "a source still repeating after a contradiction is a defect" {
    try std.testing.expectEqual(Agreement.contested, agreementOf(2, true, true));
    try std.testing.expect(Agreement.contested.isDefect());
    try std.testing.expect(!Agreement.contested.hasStaleReadings());
}

test "a contest across the host boundary is a model split" {
    // This helper applies only after callers establish that both sources state
    // the same claim. Different callback execution domains intentionally use
    // different claims and never reach this rule.
    try std.testing.expectEqual(Finding.model_split, findingOf(4, 2, 1, true));
    try std.testing.expectEqual(Finding.internal_contest, findingOf(4, 2, 1, false));
    try std.testing.expect(std.mem.indexOf(u8, Finding.model_split.guidance(), "diverged") != null);
    try std.testing.expectEqual(Side.harness, Source.rosette_interrupt_dispatch.side());
    try std.testing.expectEqual(Side.emulator, Source.xenia_startup_watch.side());
}

test "a defect outranks a reading trap" {
    // Five stale readings and one live contest must report the contest: a
    // reader who stops at the first line has to see the defect.
    try std.testing.expectEqual(Finding.model_split, findingOf(6, 5, 1, true));
    try std.testing.expectEqual(Finding.stale_readings_present, findingOf(6, 5, 0, true));
}

test "agreement without corroboration is not consistency" {
    try std.testing.expectEqual(Agreement.single_source, agreementOf(1, false, false));
    try std.testing.expectEqual(Finding.uncorroborated, findingOf(0, 0, 0, false));
    try std.testing.expect(std.mem.indexOf(u8, Finding.uncorroborated.guidance(), "absence of evidence") != null);
}

test "counters may legitimately differ and booleans may not" {
    try std.testing.expect(Claim.callback_completions.isCounter());
    try std.testing.expect(Claim.draw_completion_dispatches.isCounter());
    try std.testing.expect(!Claim.ring_initialised.isCounter());
    try std.testing.expect(!Claim.interrupt_callback_address.isCounter());
}

test "every vocabulary member carries a label and guidance" {
    inline for (@typeInfo(Claim).@"enum".fields) |field| {
        const value: Claim = @enumFromInt(field.value);
        try std.testing.expect(value.label().len != 0);
    }
    inline for (@typeInfo(Source).@"enum".fields) |field| {
        const value: Source = @enumFromInt(field.value);
        try std.testing.expect(value.label().len != 0);
        _ = value.side();
    }
    inline for (@typeInfo(Agreement).@"enum".fields) |field| {
        const value: Agreement = @enumFromInt(field.value);
        try std.testing.expect(value.label().len != 0);
        try std.testing.expect(value.guidance().len > 30);
    }
    inline for (@typeInfo(Finding).@"enum".fields) |field| {
        const value: Finding = @enumFromInt(field.value);
        try std.testing.expect(value.label().len != 0);
        try std.testing.expect(value.guidance().len > 30);
    }
    try std.testing.expect(contractIsWellFormed());
}
