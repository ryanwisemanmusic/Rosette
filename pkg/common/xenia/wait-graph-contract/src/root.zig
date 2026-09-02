//! Who waits on what, who signals it, and whether the handshake between them
//! is going anywhere.
//!
//! The existing deadlock predictor answers one question well: is something
//! parked on an object nothing has ever signalled. That is the classic failure
//! and it is not the one this run has. This run has the opposite shape:
//!
//! ```text
//! op=wait              object=0x333dec14 thread=0x7fff2160 count=1212
//! op=release_semaphore object=0x333dec14 thread=0x7fff2150 count=1218
//! op=set_event         object=0x333dec28 thread=0x7fff2150 count=1217
//! ```
//!
//! Twelve hundred matched waits and releases over six and a half billion steps.
//! Nothing is parked, nothing is unsignalled, every wait is answered — and the
//! run goes nowhere. A predictor that only looks for an unsignalled object
//! reports this as healthy, because by its question it *is*.
//!
//! ## A matched handshake is not evidence of progress
//!
//! Two threads passing a semaphore back and forth is what a working producer /
//! consumer pair looks like and what a livelocked one looks like. The counters
//! are identical. The only thing that separates them is whether anything
//! outside the handshake moved while it was cycling, which is why every verdict
//! here is gated on an independent progress axis supplied by the caller.
//!
//! That gate is not optional politeness. Without it this classifier would
//! report every healthy worker loop in the process as a livelock, and a
//! predictor that cries wolf on working code is worse than no predictor:
//! it trains a reader to skip the line that eventually matters.
//!
//! ## Orphans are two different findings
//!
//! A wait nobody signals is a stuck consumer. A signal nobody waits for is a
//! producer talking to itself — harmless on its own, and evidence that the
//! consumer it expected is somewhere else or never started. They are counted
//! apart because they send a reader to opposite threads.
//!
//! This package holds no state and observes nothing. It is the vocabulary and
//! the classifier; the ledger is `lib/diagnostics/wait_graph.zig`.

const std = @import("std");

/// What a thread did to an object.
pub const Role = enum(u8) {
    /// Blocked on it, or polled it.
    waiter,
    /// Set, released or pulsed it.
    signaller,

    pub fn label(self: Role) []const u8 {
        return switch (self) {
            .waiter => "waiter",
            .signaller => "signaller",
        };
    }
};

/// Timing evidence attached to a wait result.  The result code alone says
/// whether the kernel returned; it does not say whether the caller observed a
/// real handoff, found the object ready before parking, or timed out.  Keeping
/// this vocabulary in the build-time contract prevents the runtime ledger and
/// the Xenia-side breadcrumb parser from silently inventing different meanings
/// for the same line.
pub const WaitTiming = enum(u8) {
    unknown,
    ready_on_entry,
    blocked,
    timed_out,

    pub fn label(self: WaitTiming) []const u8 {
        return switch (self) {
            .unknown => "unknown",
            .ready_on_entry => "ready_on_entry",
            .blocked => "blocked",
            .timed_out => "timed_out",
        };
    }

    pub fn isSuccessful(self: WaitTiming) bool {
        // A result line without timing evidence is deliberately not a success
        // witness.  It may have returned, but it cannot establish whether a
        // signal was consumed or whether the caller ever parked.
        return self == .ready_on_entry or self == .blocked;
    }

    pub fn provesParkedHandoff(self: WaitTiming) bool {
        return self == .blocked;
    }
};

/// The relationship between the waits and the signals on one object.
pub const PairState = enum(u8) {
    /// Nothing has touched it.
    unobserved,
    /// Waited on and never signalled by anyone. The classic stuck consumer.
    wait_never_signalled,
    /// Signalled and never waited on. A producer whose consumer is elsewhere.
    signal_never_waited,
    /// Waits and signals are matched, and an independent axis advanced while
    /// they cycled. This is what a working handshake looks like.
    handshake_progressing,
    /// Waits and signals are matched, cycling, and nothing else moved. The
    /// handshake is alive and the run is not.
    handshake_stalled,
    /// Too few causally proven handoffs to say anything. Reported as its own
    /// state rather than folded into a healthy one: a short sample and a wait
    /// whose timing provenance is unknown are both insufficient evidence of a
    /// parked consumer.
    insufficient_sample,
    /// Every observed wait attempt timed out.  This is not a parked consumer:
    /// no continuation is waiting for a late signal at this instant, so it
    /// must not be reported as an orphan wait or a stalled handshake.
    timeout_only,

    pub fn label(self: PairState) []const u8 {
        return switch (self) {
            .unobserved => "unobserved",
            .wait_never_signalled => "wait-never-signalled",
            .signal_never_waited => "signal-never-waited",
            .handshake_progressing => "handshake-progressing",
            .handshake_stalled => "HANDSHAKE-STALLED",
            .insufficient_sample => "insufficient-sample",
            .timeout_only => "timeout-only",
        };
    }

    /// Whether this state is a finding rather than an observation.
    pub fn isFinding(self: PairState) bool {
        return switch (self) {
            .wait_never_signalled, .handshake_stalled => true,
            .unobserved,
            .signal_never_waited,
            .handshake_progressing,
            .insufficient_sample,
            .timeout_only,
            => false,
        };
    }

    pub fn guidance(self: PairState) []const u8 {
        return switch (self) {
            .unobserved => "no thread has waited on or signalled this object",
            .wait_never_signalled => "a thread is waiting on an object nothing has ever signalled. The waiter is not waiting for a late signal, it is waiting for a code path that has not run — so find who was supposed to signal it and confirm that code was reached at all",
            .signal_never_waited => "this object is signalled and nobody waits on it. Harmless in itself, and it means the consumer the producer expects is either waiting on a different object or was never started. Check whether the waiter names the same object by a different address",
            .handshake_progressing => "waits and signals are matched and something outside the handshake advanced while they cycled. This is a working producer/consumer pair",
            .handshake_stalled => "waits and signals are matched and cycling, and nothing outside the handshake moved. Both threads are alive, neither is stuck, and the pair is not accomplishing anything: the question is not who failed to signal but what the woken thread does next and why it comes straight back",
            .insufficient_sample => "too few waits are proven to have parked to distinguish a handshake from a coincidence. Ready-on-entry and duration-derived result labels are observations, not missing-signal evidence",
            .timeout_only => "all observed wait attempts timed out, so this is a deadline/polling observation rather than a parked consumer. Keep it in the timeout ledger instead of calling it an orphan wait",
        };
    }
};

/// The reading for a whole graph.
pub const Verdict = enum(u8) {
    /// Nothing observed.
    idle,
    /// Every object either progresses or has too small a sample.
    healthy,
    /// At least one object is signalled and never waited on, and nothing worse.
    orphan_signal,
    /// At least one object is waited on and never signalled.
    orphan_wait,
    /// At least one matched handshake is cycling with nothing else moving.
    handshake_without_progress,
    /// Two threads each wait on an object only the other signals.
    wait_cycle,
    /// One or more wait attempts expired, but no non-timeout wait is currently
    /// available to prove that a consumer is parked.  The timeout gate owns
    /// whether repeated expiries eventually become a fault.
    timeout_without_signal,

    pub fn label(self: Verdict) []const u8 {
        return switch (self) {
            .idle => "idle",
            .healthy => "healthy",
            .orphan_signal => "orphan_signal",
            .orphan_wait => "orphan_wait",
            .handshake_without_progress => "handshake_without_progress",
            .wait_cycle => "WAIT_CYCLE",
            .timeout_without_signal => "timeout_without_signal",
        };
    }

    /// Whether a longer run could resolve this on its own.
    pub fn selfResolving(self: Verdict) bool {
        return switch (self) {
            .idle, .healthy, .orphan_signal, .timeout_without_signal => true,
            .orphan_wait, .handshake_without_progress, .wait_cycle => false,
        };
    }

    pub fn guidance(self: Verdict) []const u8 {
        return switch (self) {
            .idle => "no wait or signal has been observed, so nothing can be said about the graph",
            .healthy => "every observed handshake advanced something outside itself while it cycled",
            .orphan_signal => "an object is signalled that nobody waits on. Not a stall by itself: it says the consumer is waiting somewhere else, or on the same object under a different address",
            .orphan_wait => "a thread is parked on an object nothing has ever signalled. This is a stuck consumer and a longer run will not free it",
            .handshake_without_progress => "a matched wait/signal pair is cycling and nothing outside it is moving. Both threads are alive and neither is blocked, so this will not appear in any deadlock check — the pair is doing work that accomplishes nothing, and the woken thread's next action is the question",
            .wait_cycle => "two threads each wait on an object only the other signals. Neither can proceed and neither is idle; this is a genuine cycle and it does not resolve",
            .timeout_without_signal => "the observed waits expired without a signal, but no non-timeout consumer is currently parked. Treat this as a deadline/polling result and let the timeout policy decide whether more evidence is required",
        };
    }
};

/// Below this many matched pairs, an object's shape is a coincidence rather
/// than a pattern. Deliberately low: the run this was written against cycles
/// twelve hundred times, and a threshold tuned to that would miss a pair that
/// has only gone round thirty.
pub const minimum_handshake_sample: u64 = 8;

/// The classifier.
///
/// `progress_advanced` is the independent axis: whether anything outside this
/// handshake moved while it was cycling. Without it a working worker loop and a
/// livelock are indistinguishable, so it is a required argument rather than an
/// optional refinement.
pub fn classifyPair(
    waits: u64,
    signals: u64,
    progress_advanced: bool,
) PairState {
    if (waits == 0 and signals == 0) return .unobserved;
    if (waits == 0) return .signal_never_waited;
    if (signals == 0) return .wait_never_signalled;
    const matched = @min(waits, signals);
    if (matched < minimum_handshake_sample) return .insufficient_sample;
    return if (progress_advanced) .handshake_progressing else .handshake_stalled;
}

/// Classify a ledger record without allowing timed-out attempts to masquerade
/// as parked waits.  `waits` is the total attempt count; callers that retain
/// timing evidence pass the number of those attempts that expired.
pub fn classifyPairWithTimeouts(
    waits: u64,
    signals: u64,
    timed_out_waits: u64,
    progress_advanced: bool,
) PairState {
    if (timed_out_waits != 0 and timed_out_waits >= waits) return .timeout_only;
    return classifyPair(waits -| timed_out_waits, signals, progress_advanced);
}

/// Classify only the wait results that prove the consumer actually parked.
///
/// Xenia's `wait_disposition=blocked` historically meant that a successful
/// wait took non-zero wall time. That duration is not causal proof: a
/// pre-signalled semaphore can be consumed after enough logging or scheduling
/// overhead to cross the millisecond boundary. Callers therefore pass the
/// separately proven blocked-success count. Unknown-timing and ready-on-entry
/// waits remain visible in the ledger, but cannot manufacture an orphan wait
/// or a stalled handshake.
pub fn classifyPairWithTiming(
    waits: u64,
    signals: u64,
    timed_out_waits: u64,
    blocked_successes: u64,
    progress_advanced: bool,
) PairState {
    if (waits == 0 and signals == 0) return .unobserved;
    if (waits == 0) return .signal_never_waited;
    if (timed_out_waits >= waits) return .timeout_only;

    const non_timeout_waits = waits - timed_out_waits;
    const proven_parked = @min(blocked_successes, non_timeout_waits);
    if (proven_parked == 0) return .insufficient_sample;
    return classifyPair(proven_parked, signals, progress_advanced);
}

pub fn verdictOf(
    observed_objects: usize,
    orphan_waits: usize,
    orphan_signals: usize,
    stalled_handshakes: usize,
    cycles: usize,
) Verdict {
    if (observed_objects == 0) return .idle;
    // Ordered by how little a longer run can do about it. A cycle is the most
    // final, and an orphan signal is the least — reporting the mild one over
    // the severe would send a reader to the wrong thread.
    if (cycles != 0) return .wait_cycle;
    if (stalled_handshakes != 0) return .handshake_without_progress;
    if (orphan_waits != 0) return .orphan_wait;
    if (orphan_signals != 0) return .orphan_signal;
    return .healthy;
}

/// The timeout-only refinement is deliberately lower priority than every
/// genuine graph finding.  A late timeout cannot hide a stalled handshake or
/// an orphaned non-timeout consumer, but it is still visible in the report.
pub fn verdictOfWithTimeouts(
    observed_objects: usize,
    orphan_waits: usize,
    orphan_signals: usize,
    stalled_handshakes: usize,
    cycles: usize,
    timeout_only_objects: usize,
) Verdict {
    const base = verdictOf(
        observed_objects,
        orphan_waits,
        orphan_signals,
        stalled_handshakes,
        cycles,
    );
    if (base == .healthy and timeout_only_objects != 0) return .timeout_without_signal;
    return base;
}

pub fn contractIsWellFormed() bool {
    if (classifyPair(0, 0, false) != .unobserved) return false;
    if (classifyPair(0, 5, false) != .signal_never_waited) return false;
    if (classifyPair(5, 0, false) != .wait_never_signalled) return false;
    if (classifyPair(2, 2, false) != .insufficient_sample) return false;
    if (classifyPair(1212, 1218, false) != .handshake_stalled) return false;
    if (classifyPair(1212, 1218, true) != .handshake_progressing) return false;
    if (classifyPairWithTimeouts(4, 0, 4, false) != .timeout_only) return false;
    if (classifyPairWithTimeouts(14, 14, 4, false) != .handshake_stalled) return false;
    if (classifyPairWithTiming(25, 0, 0, 0, false) != .insufficient_sample) return false;
    if (classifyPairWithTiming(25, 0, 0, 1, false) != .wait_never_signalled) return false;
    if (classifyPairWithTiming(25, 25, 0, 25, true) != .handshake_progressing) return false;

    // The gate is what stops a working worker loop being called a livelock.
    if (classifyPair(1000, 1000, true).isFinding()) return false;
    if (!classifyPair(1000, 1000, false).isFinding()) return false;
    if (!classifyPair(5, 0, false).isFinding()) return false;
    if (classifyPair(0, 5, false).isFinding()) return false;

    if (verdictOf(0, 0, 0, 0, 0) != .idle) return false;
    if (verdictOf(4, 0, 0, 0, 0) != .healthy) return false;
    if (verdictOf(4, 0, 1, 0, 0) != .orphan_signal) return false;
    if (verdictOf(4, 1, 1, 0, 0) != .orphan_wait) return false;
    if (verdictOf(4, 1, 1, 1, 0) != .handshake_without_progress) return false;
    if (verdictOf(4, 1, 1, 1, 1) != .wait_cycle) return false;
    if (verdictOfWithTimeouts(4, 0, 0, 0, 0, 1) != .timeout_without_signal) return false;

    if (!Verdict.healthy.selfResolving()) return false;
    if (!Verdict.orphan_signal.selfResolving()) return false;
    if (Verdict.orphan_wait.selfResolving()) return false;
    if (Verdict.handshake_without_progress.selfResolving()) return false;
    if (Verdict.wait_cycle.selfResolving()) return false;
    if (!Verdict.timeout_without_signal.selfResolving()) return false;
    if (!WaitTiming.blocked.isSuccessful()) return false;
    if (WaitTiming.unknown.isSuccessful()) return false;
    if (!WaitTiming.blocked.provesParkedHandoff()) return false;
    if (WaitTiming.ready_on_entry.provesParkedHandoff()) return false;
    if (WaitTiming.timed_out.isSuccessful()) return false;
    return true;
}

test "a matched handshake with nothing moving is the live case" {
    // 1212 waits against 1218 releases over 6.5B steps, and no independent
    // axis advanced. Every deadlock check calls this healthy because nothing
    // is parked and nothing is unsignalled.
    const state = classifyPair(1212, 1218, false);
    try std.testing.expectEqual(PairState.handshake_stalled, state);
    try std.testing.expect(state.isFinding());
    try std.testing.expect(std.mem.indexOf(u8, state.guidance(), "not accomplishing anything") != null);
}

test "the same handshake with progress is a working worker loop" {
    // The gate that stops this classifier crying wolf on healthy code.
    const state = classifyPair(1212, 1218, true);
    try std.testing.expectEqual(PairState.handshake_progressing, state);
    try std.testing.expect(!state.isFinding());
}

test "an orphan wait and an orphan signal are different findings" {
    try std.testing.expectEqual(PairState.wait_never_signalled, classifyPair(9, 0, false));
    try std.testing.expectEqual(PairState.signal_never_waited, classifyPair(0, 9, false));
    // Only the first is a stall; the second says the consumer is elsewhere.
    try std.testing.expect(classifyPair(9, 0, false).isFinding());
    try std.testing.expect(!classifyPair(0, 9, false).isFinding());
    try std.testing.expect(std.mem.indexOf(u8, PairState.signal_never_waited.guidance(), "different address") != null);
}

test "a small sample is not a pattern" {
    // Two round trips prove nothing, and calling them a livelock would bury
    // the object that has gone round a thousand times.
    try std.testing.expectEqual(PairState.insufficient_sample, classifyPair(2, 3, false));
    try std.testing.expect(!classifyPair(2, 3, false).isFinding());
    try std.testing.expectEqual(
        PairState.handshake_stalled,
        classifyPair(minimum_handshake_sample, minimum_handshake_sample, false),
    );
}

test "wait timing keeps completion and handoff evidence distinct" {
    try std.testing.expect(WaitTiming.ready_on_entry.isSuccessful());
    try std.testing.expect(WaitTiming.blocked.isSuccessful());
    try std.testing.expect(WaitTiming.blocked.provesParkedHandoff());
    try std.testing.expect(!WaitTiming.ready_on_entry.provesParkedHandoff());
    try std.testing.expect(!WaitTiming.unknown.provesParkedHandoff());
    try std.testing.expect(!WaitTiming.timed_out.isSuccessful());
    try std.testing.expectEqualStrings("blocked", WaitTiming.blocked.label());
}

test "verdicts are ordered by how little a longer run can do" {
    // A cycle outranks a stalled handshake outranks an orphan wait outranks an
    // orphan signal: reporting the mild one sends a reader to the wrong thread.
    try std.testing.expectEqual(Verdict.wait_cycle, verdictOf(9, 3, 3, 3, 1));
    try std.testing.expectEqual(Verdict.handshake_without_progress, verdictOf(9, 3, 3, 3, 0));
    try std.testing.expectEqual(Verdict.orphan_wait, verdictOf(9, 3, 3, 0, 0));
    try std.testing.expectEqual(Verdict.orphan_signal, verdictOf(9, 0, 3, 0, 0));
    try std.testing.expect(!Verdict.wait_cycle.selfResolving());
    try std.testing.expect(Verdict.orphan_signal.selfResolving());
}

test "every state and verdict carries guidance a reader can act on" {
    inline for (@typeInfo(PairState).@"enum".fields) |field| {
        const value: PairState = @enumFromInt(field.value);
        try std.testing.expect(value.label().len != 0);
        try std.testing.expect(value.guidance().len > 30);
    }
    inline for (@typeInfo(Verdict).@"enum".fields) |field| {
        const value: Verdict = @enumFromInt(field.value);
        try std.testing.expect(value.label().len != 0);
        try std.testing.expect(value.guidance().len > 30);
    }
    inline for (@typeInfo(Role).@"enum".fields) |field| {
        const value: Role = @enumFromInt(field.value);
        try std.testing.expect(value.label().len != 0);
    }
    try std.testing.expect(contractIsWellFormed());
}
