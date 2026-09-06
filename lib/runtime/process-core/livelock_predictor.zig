//! LIVELOCK PREDICTOR — ReleaseFast-friendly guest wait-cycle signatures.
//!
//! A guest that stops making forward progress while repeating the same
//! synchronization operations is not crashing: nothing faults, no near-null
//! receiver appears, the CPU stays busy, and the log rotates through the same
//! handful of lines forever. The only signature is repetition — the same
//! object waited on, set, and released, with no new content and no ring
//! advance.
//!
//! This module watches the guest's synchronization operations as reported by
//! the emulator's own kernel tracing (mirrored through the guest log bridge):
//! `KeWaitForSingleObject`, `KeSetEvent`, `KeReleaseSemaphore`. Each distinct
//! (operation, object) pair keeps a hit count, the first and last step it was
//! seen, and the waiting thread, in a bounded table. A signature whose count
//! grows while the ring write pointer is not advancing is a livelock
//! prediction: the guest is parked on an object nobody will ever signal.
//!
//! Emission is throttled exactly like the near-null predictor: first sight,
//! then doubling thresholds, capped per signature, so a hot wait loop cannot
//! flood the log. `dump` is called from the terminal diagnostics so a run
//! that ends inside a wait cycle names the objects it was cycling on.
//!
//! Cost model (the ReleaseFast contract): `note` is one prefix/hash probe per
//! matching guest log line — reached only from the log mirror path, never
//! from the instruction stream. No allocation, no unbounded state, saturating
//! counters. The caller decides whether the ring is stalled (its knowledge,
//! not this module's) and passes it in; this module decides whether the
//! repetition is worth naming.

const std = @import("std");
const machoCapturePrint = @import("dyld").event_log.machoCapturePrint;

pub const SIGNATURE_CAPACITY: usize = 32;
pub const RECENT_CAPACITY: usize = 16;
/// Cap per-signature emissions so a recurring wait loop cannot spam the log.
pub const MAX_EMISSIONS_PER_SIGNATURE: u32 = 4;
/// A signature must be seen at least this many times before it can be called
/// a cycle. One or two waits on an object is a handshake, not a livelock.
pub const MIN_CYCLE_COUNT: u32 = 4;

/// The synchronization operation the guest performed on an object.
pub const Operation = enum(u8) {
    /// `KeWaitForSingleObject` returned signaled (or the wait was consumed).
    wait,
    /// `KeWaitForSingleObject` returned `STATUS_TIMEOUT` — the guest is
    /// re-polling an object that never becomes ready.
    wait_timeout,
    /// `KeSetEvent` — the guest is raising an event.
    set_event,
    /// `KeReleaseSemaphore` — the guest is releasing a semaphore.
    release_semaphore,

    pub fn label(self: Operation) []const u8 {
        return switch (self) {
            .wait => "wait",
            .wait_timeout => "wait_timeout",
            .set_event => "set_event",
            .release_semaphore => "release_semaphore",
        };
    }
};

/// How the authoritative wait audit accounted for a retained signature.
///
/// Repetition and health are different questions.  A signal-only producer,
/// a finite polling timeout, and a one-off breadcrumb are all accounted-for
/// observations, but none is a healthy producer/consumer pump.  Keeping those
/// outcomes distinct prevents the final predictor from turning a classified
/// caution into an "unaccounted livelock" while still retaining the evidence.
pub const Accounting = enum(u8) {
    /// The signature has not crossed the recurrence threshold. It is retained
    /// as a breadcrumb, never promoted to a livelock finding.
    immature,
    expected_pump,
    expected_bounded,
    signal_only,
    bounded_timeout,
    insufficient_evidence,
    problem_stalled,
    problem_never_ready,
    /// No authoritative wait-audit subject matched this mature signature.
    no_audit,

    pub fn label(self: Accounting) []const u8 {
        return switch (self) {
            .immature => "immature",
            .expected_pump => "expected_pump",
            .expected_bounded => "expected_bounded",
            .signal_only => "signal_only",
            .bounded_timeout => "bounded_timeout",
            .insufficient_evidence => "insufficient_evidence",
            .problem_stalled => "PROBLEM_STALLED",
            .problem_never_ready => "PROBLEM_NEVER_READY",
            .no_audit => "no_audit",
        };
    }

    pub fn isHealthy(self: Accounting) bool {
        return self == .expected_pump or self == .expected_bounded;
    }

    pub fn isClassified(self: Accounting) bool {
        return self != .immature and self != .no_audit;
    }

    pub fn isProblem(self: Accounting) bool {
        return self == .problem_stalled or self == .problem_never_ready;
    }
};

const Signature = struct {
    valid: bool = false,
    op: Operation = .wait,
    /// Guest pointer of the object operated on (the semaphore/event address).
    object: u64 = 0,
    /// Last thread seen performing this operation (0 if unknown).
    thread: u64 = 0,
    /// Guest PC where the operation was last observed, when the observing
    /// state exposes a register file. Named because "find who waits on it"
    /// needs a place to look: the symbol at this PC is where the cycle spins.
    pc: u64 = 0,
    count: u32 = 0,
    emissions: u32 = 0,
    first_seen_step: u64 = 0,
    last_seen_step: u64 = 0,
};

const Recent = struct {
    op: Operation = .wait,
    object: u64 = 0,
    step: u64 = 0,
};

/// What the retained signatures say about how the run ended.
///
/// The dump used to be a list. Sixteen signatures and sixteen recent
/// operations, every one of them printed, with nothing saying whether the run
/// ended inside a livelock or inside a working producer/consumer pump — and
/// those look identical in a list of repetition counts. The distinction is not
/// available to this module on its own; it comes from the wait audit, which
/// holds the one thing repetition cannot tell you: whether anything else in
/// the run advanced alongside the pattern.
pub const Termination = enum(u8) {
    /// Nothing was retained. The run did not end in a wait pattern at all.
    quiet,
    /// Retained breadcrumbs exist, but none reached the recurrence threshold.
    /// A first sighting is evidence to keep, not a livelock conclusion.
    insufficient_evidence,
    /// Every retained signature is a handshake the audit judged healthy: a
    /// bounded wait that completed, or a pump that kept its consumer fed.
    healthy_pumps_only,
    /// Every mature signature was classified by the wait audit, but at least
    /// one was a caution or an explicit problem rather than a healthy pump.
    classified_findings,
    /// At least one signature recurred while the audit could not account for
    /// it. This is the one worth reading the recent window for.
    unaccounted_cycle,

    pub fn label(self: Termination) []const u8 {
        return switch (self) {
            .quiet => "quiet",
            .insufficient_evidence => "insufficient-evidence",
            .healthy_pumps_only => "healthy-pumps-only",
            .classified_findings => "classified-findings",
            .unaccounted_cycle => "unaccounted-cycle",
        };
    }

    pub fn meaning(self: Termination) []const u8 {
        return switch (self) {
            .quiet => "no wait signature was retained; the run did not end inside a synchronization pattern and nothing here bears on why it stopped",
            .insufficient_evidence => "wait breadcrumbs were retained, but none crossed the recurrence threshold. A first sighting is not a livelock, so the predictor keeps it as evidence without assigning a cycle verdict",
            .healthy_pumps_only => "every retained signature is a handshake the wait audit accounted for — a bounded wait that completed, or a pump whose consumer kept up. Repetition here is what a working producer/consumer looks like; the reason the run stopped is somewhere else, and the detail is collapsed so it does not read as a finding",
            .classified_findings => "every mature signature has an authoritative wait-audit classification. Some are cautions or explicit wait findings, but none is an unclassified cycle; read those classifications together with the wait graph rather than treating them as an unexplained livelock",
            .unaccounted_cycle => "a signature recurred that the wait audit could not account for. This is the pattern to read the recent window against: the question is not who failed to signal, but what the woken thread does next and why it comes straight back",
        };
    }
};

pub const Predictor = struct {
    signatures: [SIGNATURE_CAPACITY]Signature = [_]Signature{.{}} ** SIGNATURE_CAPACITY,
    recent: [RECENT_CAPACITY]Recent = [_]Recent{.{}} ** RECENT_CAPACITY,
    recent_index: usize = 0,
    recent_filled: bool = false,
    observations: u64 = 0,
    distinct_signatures: u32 = 0,
    emissions: u64 = 0,
    /// Signatures the wait audit judged healthy, so their detail was not
    /// printed. Counted rather than silent: a predictor that quietly stops
    /// reporting is indistinguishable from one that stopped working.
    suppressed: u64 = 0,

    /// Record one synchronization operation. `thread` is the guest thread that
    /// performed it (0 when unknown — host-originated lines); without it the
    /// guidance "find who waits on it" would name no one. `ring_stalled` is
    /// the caller's verdict on forward progress (the ring write pointer has
    /// not advanced for a long window, or no ring publication has ever been
    /// seen); a signature is only *predicted* as a livelock when the ring is
    /// stalled.
    pub fn note(self: *Predictor, state: anytype, op: Operation, object: u64, thread: u64, ring_stalled: bool) void {
        self.observations +|= 1;
        const signature = self.findOrInsert(op, object) orelse return;
        if (thread != 0) signature.thread = thread;
        // S2 (audit): capture where in the guest the operation ran. The
        // guest-log bridge runs on the thread that wrote the line, so the
        // active register file's RIP is the guest's own site. Test states
        // expose only `executed_steps`; only real states have `regs`.
        if (comptime @hasField(@TypeOf(state.*), "regs")) {
            signature.pc = state.regs.rip;
        }
        self.pushRecent(op, object, state.executed_steps);

        const step = state.executed_steps;
        const first_sight = signature.count == 0;
        signature.count +|= 1;
        signature.last_seen_step = step;
        if (first_sight) signature.first_seen_step = step;

        // Everything below is gated on `ring_stalled`: this is a livelock
        // checker, not a wait tracer, and silence while the ring advances is
        // the health signal. First sight names the object the guest first
        // waited on during the stall; the doubling thresholds then report the
        // same (operation, object) recurring, capped per signature.
        if (ring_stalled) {
            const doubling_threshold = (signature.count & (signature.count - 1)) == 0;
            const cycle_confirmed = signature.count >= MIN_CYCLE_COUNT;
            if (first_sight or
                (cycle_confirmed and doubling_threshold and
                    signature.emissions < MAX_EMISSIONS_PER_SIGNATURE))
            {
                signature.emissions +|= 1;
                self.emit(state, signature);
            }
        }
    }

    /// Dump every retained wait-cycle signature with readable counts. Called
    /// from terminal diagnostics so a run that ended inside a wait cycle
    /// names the objects it was cycling on instead of reading empty.
    ///
    /// Returns the termination verdict so the caller can decide whether the
    /// recent window is worth printing.
    pub fn dump(self: *Predictor, state: anytype, reason: []const u8) Termination {
        var retained: usize = 0;
        var accounted: usize = 0;
        var healthy: usize = 0;
        var classified: usize = 0;
        var immature: usize = 0;
        var unaccounted: usize = 0;
        for (&self.signatures) |*signature| {
            if (!signature.valid) continue;
            retained += 1;
            const accounting = self.accountingFor(state, signature);
            switch (accounting) {
                .immature => {
                    accounted += 1;
                    immature += 1;
                },
                .expected_pump, .expected_bounded => {
                    accounted += 1;
                    healthy += 1;
                },
                .no_audit => {
                    unaccounted += 1;
                    machoCapturePrint(
                        "LIVELOCK PREDICTOR: signature op={s} object=0x{x} thread=0x{x} pc=0x{x} count={d} first_seen_step={d} last_seen_step={d} emissions={d} accounting=no_audit accounted=NO\n",
                        .{
                            signature.op.label(),
                            signature.object,
                            signature.thread,
                            signature.pc,
                            signature.count,
                            signature.first_seen_step,
                            signature.last_seen_step,
                            signature.emissions,
                        },
                    );
                },
                else => {
                    accounted += 1;
                    classified += 1;
                    machoCapturePrint(
                        "LIVELOCK PREDICTOR: signature op={s} object=0x{x} thread=0x{x} pc=0x{x} count={d} first_seen_step={d} last_seen_step={d} emissions={d} accounting={s} accounted=YES; the wait audit classified this signature, so it is not an unexplained cycle\n",
                        .{
                            signature.op.label(),
                            signature.object,
                            signature.thread,
                            signature.pc,
                            signature.count,
                            signature.first_seen_step,
                            signature.last_seen_step,
                            signature.emissions,
                            accounting.label(),
                        },
                    );
                },
            }
        }
        const termination: Termination = if (retained == 0)
            .quiet
        else if (unaccounted == 0)
            if (classified != 0)
                .classified_findings
            else if (immature != 0)
                .insufficient_evidence
            else
                .healthy_pumps_only
        else
            .unaccounted_cycle;
        if (accounted != 0) machoCapturePrint(
            "LIVELOCK PREDICTOR: accounting healthy={d} classified={d} immature={d} accounted={d} unaccounted={d}; mature signatures are either healthy pumps or explicitly classified findings, and immature breadcrumbs are not promoted to cycles\n",
            .{ healthy, classified, immature, accounted, unaccounted },
        );
        machoCapturePrint(
            "LIVELOCK PREDICTOR: dump reason={s} termination={s} distinct={d} retained={d} accounted={d} unaccounted={d} observations={d} recent_window={d} emissions={d} suppressed_by_audit={d} step={d}; {s}\n",
            .{
                reason,
                termination.label(),
                self.distinct_signatures,
                retained,
                accounted,
                unaccounted,
                self.observations,
                self.recentCount(),
                self.emissions,
                self.suppressed,
                state.executed_steps,
                termination.meaning(),
            },
        );
        return termination;
    }

    /// Match a retained signature to the authoritative wait audit.
    ///
    /// This deliberately returns more than a boolean.  `signal_only`,
    /// `bounded_timeout`, and `insufficient_evidence` are all meaningful
    /// classifications, while `problem_*` remains a real finding even though
    /// it is no longer an unexplained livelock.  A boolean used to collapse all
    /// of those into the same false "unaccounted" bucket.
    fn accountingFor(self: *Predictor, state: anytype, signature: *const Signature) Accounting {
        _ = self;
        if (signature.count < MIN_CYCLE_COUNT) return .immature;
        if (comptime !@hasField(@TypeOf(state.*), "wait_audit")) return .no_audit;
        const audit = &state.wait_audit;
        for (audit.subjects[0..audit.count]) |subject| {
            if (subject.object != signature.object) continue;
            const classification = audit.classify(subject, state.executed_steps);
            return accountingFromClassificationName(@tagName(classification));
        }
        return .no_audit;
    }

    fn accountingFromClassificationName(name: []const u8) Accounting {
        if (std.mem.eql(u8, name, "expected_pump")) return .expected_pump;
        if (std.mem.eql(u8, name, "expected_bounded")) return .expected_bounded;
        if (std.mem.eql(u8, name, "signal_only")) return .signal_only;
        if (std.mem.eql(u8, name, "bounded_timeout")) return .bounded_timeout;
        if (std.mem.eql(u8, name, "problem_stalled")) return .problem_stalled;
        if (std.mem.eql(u8, name, "problem_never_ready")) return .problem_never_ready;
        if (std.mem.eql(u8, name, "insufficient_evidence")) return .insufficient_evidence;
        return .no_audit;
    }

    /// The most recent wait operations, oldest first, for correlation.
    pub fn dumpRecent(self: *Predictor, state: anytype) void {
        const count = self.recentCount();
        if (count == 0) return;
        machoCapturePrint(
            "LIVELOCK PREDICTOR: recent wait operations ({d}) at step={d}:\n",
            .{ count, state.executed_steps },
        );
        for (0..count) |ordinal| {
            const recent = self.recentChronological(ordinal) orelse continue;
            machoCapturePrint(
                "  [{d}] op={s} object=0x{x} step={d}\n",
                .{ ordinal, recent.op.label(), recent.object, recent.step },
            );
        }
    }

    fn emit(self: *Predictor, state: anytype, signature: *const Signature) void {
        // A pattern the audit has judged healthy is not printed.
        //
        // This predictor detects repetition, and repetition is what a working
        // producer/consumer pump looks like. Printing every one buries the one
        // that matters: the observed run emitted a scatter of entries for an
        // audio pump doing its job while a genuinely stalled rotation sat among
        // them indistinguishable. The audit decides, because it holds the one
        // thing this predictor cannot see — whether anything else in the run
        // advanced alongside the pattern.
        const accounting = self.accountingFor(state, signature);
        if (accounting.isClassified() and !accounting.isProblem()) {
            self.suppressed +|= 1;
            return;
        }
        self.emissions +|= 1;
        const guidance: []const u8 = switch (signature.op) {
            .wait => "the guest is parked on an object that never became ready; find who should signal it and confirm they ran",
            .wait_timeout => "the guest keeps polling an object that never becomes ready; every wait times out — the signal that should release it is not arriving",
            .set_event => "the guest keeps raising this event without forward progress; find who waits on it and why the cycle does not complete",
            .release_semaphore => "the guest keeps releasing this semaphore without forward progress; find who consumes it and why the cycle does not complete",
        };
        const kind: []const u8 = if (signature.count == 1)
            "first_sight"
        else if (signature.count == MIN_CYCLE_COUNT)
            "wait_cycle"
        else
            "recurrence";
        machoCapturePrint(
            "LIVELOCK PREDICTOR: {s} op={s} object=0x{x} thread=0x{x} pc=0x{x} count={d} first_seen_step={d} last_seen_step={d} ring_stalled=YES step={d} accounting={s}; {s}\n",
            .{
                kind,
                signature.op.label(),
                signature.object,
                signature.thread,
                signature.pc,
                signature.count,
                signature.first_seen_step,
                signature.last_seen_step,
                state.executed_steps,
                accounting.label(),
                guidance,
            },
        );
    }

    fn findOrInsert(self: *Predictor, op: Operation, object: u64) ?*Signature {
        const hash = hashSignature(op, object);
        var index: usize = @intCast(hash % SIGNATURE_CAPACITY);
        var first_empty: ?usize = null;
        var probes: usize = 0;
        while (probes < SIGNATURE_CAPACITY) : (probes += 1) {
            const signature = &self.signatures[index];
            if (!signature.valid) {
                if (first_empty == null) first_empty = index;
                break;
            }
            if (signature.op == op and signature.object == object) return signature;
            index = (index + 1) % SIGNATURE_CAPACITY;
        }
        if (first_empty) |slot| {
            self.signatures[slot] = .{
                .valid = true,
                .op = op,
                .object = object,
                .thread = 0,
                .count = 0,
                .emissions = 0,
                .first_seen_step = 0,
                .last_seen_step = 0,
            };
            self.distinct_signatures +|= 1;
            return &self.signatures[slot];
        }
        // Table full of distinct signatures. Evict the least important one —
        // lowest hit count, oldest step as a tiebreak — so a hot recurring
        // wait is never displaced by a one-off.
        var victim: ?usize = null;
        var victim_count: u32 = std.math.maxInt(u32);
        var victim_step: u64 = std.math.maxInt(u64);
        for (&self.signatures, 0..) |*signature, i| {
            if (!signature.valid) continue;
            const better_count = signature.count < victim_count;
            const same_count = signature.count == victim_count and signature.last_seen_step < victim_step;
            if (better_count or same_count) {
                victim = i;
                victim_count = signature.count;
                victim_step = signature.last_seen_step;
            }
        }
        const slot = victim orelse return null;
        self.signatures[slot] = .{
            .valid = true,
            .op = op,
            .object = object,
            .thread = 0,
            .pc = 0,
            .count = 0,
            .emissions = 0,
            .first_seen_step = 0,
            .last_seen_step = 0,
        };
        return &self.signatures[slot];
    }

    fn pushRecent(self: *Predictor, op: Operation, object: u64, step: u64) void {
        self.recent[self.recent_index] = .{ .op = op, .object = object, .step = step };
        self.recent_index += 1;
        if (self.recent_index == RECENT_CAPACITY) {
            self.recent_index = 0;
            self.recent_filled = true;
        }
    }

    fn recentCount(self: *const Predictor) usize {
        return if (self.recent_filled) RECENT_CAPACITY else self.recent_index;
    }

    fn recentChronological(self: *const Predictor, ordinal: usize) ?Recent {
        const count = self.recentCount();
        if (ordinal >= count) return null;
        const start: usize = if (self.recent_filled) self.recent_index else 0;
        return self.recent[(start + ordinal) % RECENT_CAPACITY];
    }

    fn hashSignature(op: Operation, object: u64) u64 {
        var hash: u64 = 0x9e37_79b9_7f4a_7c15;
        hash ^= @intFromEnum(op);
        hash *%= 0x100_0000_01b3;
        hash ^= object;
        hash *%= 0x100_0000_01b3;
        return hash;
    }
};

// The observed livelock: the GPU command thread created semaphore 827CEC14
// (count 0, max 6) and events F8000168/F800016C, then rotated through
// wait/set/release forever while the ring write pointer never moved again.
test "wait cycle on a live object with a stalled ring is predicted" {
    const TestState = struct {
        executed_steps: u64 = 0,
    };
    var predictor = Predictor{};
    var state = TestState{};

    // Healthy handshake: a few waits while the ring advances. Nothing fires.
    state.executed_steps = 1000;
    predictor.note(&state, .wait, 0x827CEC14, 0x7fff2110, false);
    predictor.note(&state, .set_event, 0x827CEC28, 0x7fff2080, false);
    predictor.note(&state, .wait, 0x827CEC14, 0x7fff2110, false);
    try std.testing.expectEqual(@as(u64, 3), predictor.observations);
    try std.testing.expectEqual(@as(u32, 2), predictor.distinct_signatures);

    // The stall: the ring stops advancing and the same wait repeats. First
    // prediction fires at the MIN_CYCLE_COUNT doubling threshold.
    state.executed_steps = 2000;
    predictor.note(&state, .wait, 0x827CEC14, 0x7fff2110, true);
    state.executed_steps = 3000;
    predictor.note(&state, .wait, 0x827CEC14, 0x7fff2110, true);
    try std.testing.expectEqual(@as(u64, 5), predictor.observations);
    const signature = predictor.findOrInsert(.wait, 0x827CEC14).?;
    try std.testing.expectEqual(@as(u32, 4), signature.count);
    try std.testing.expectEqual(@as(u32, 1), signature.emissions);
    try std.testing.expectEqual(@as(u64, 1), predictor.emissions);
    // The thread that performed the operation is named, so the guidance
    // "find who waits on it" has an answer.
    try std.testing.expectEqual(@as(u64, 0x7fff2110), signature.thread);
}

// The emitted line names where in the guest the cycle spins, so a reader can
// resolve the symbol at that PC instead of staring at an object address.
test "the guest PC of the operation is captured when the state has registers" {
    const TestState = struct {
        executed_steps: u64 = 0,
        regs: struct { rip: u64 = 0 } = .{ .rip = 0x82581ad0 },
    };
    var predictor = Predictor{};
    var state = TestState{};
    state.executed_steps = 100;
    state.regs.rip = 0x82581ad0;
    predictor.note(&state, .set_event, 0x827CEC28, 0x7fff2080, true);
    try std.testing.expectEqual(@as(u64, 0x82581ad0), predictor.findOrInsert(.set_event, 0x827CEC28).?.pc);
}

test "the last observed thread is retained per signature" {
    const TestState = struct {
        executed_steps: u64 = 0,
    };
    var predictor = Predictor{};
    var state = TestState{};

    state.executed_steps = 100;
    predictor.note(&state, .wait, 0x827CEC14, 0x7fff2110, false);
    try std.testing.expectEqual(@as(u64, 0x7fff2110), predictor.findOrInsert(.wait, 0x827CEC14).?.thread);
    // A later operation by a different thread updates the name.
    state.executed_steps = 200;
    predictor.note(&state, .wait, 0x827CEC14, 0x7fff20e0, false);
    try std.testing.expectEqual(@as(u64, 0x7fff20e0), predictor.findOrInsert(.wait, 0x827CEC14).?.thread);
    // An unknown thread never overwrites a known one.
    predictor.note(&state, .wait, 0x827CEC14, 0, false);
    try std.testing.expectEqual(@as(u64, 0x7fff20e0), predictor.findOrInsert(.wait, 0x827CEC14).?.thread);
}

test "timeout waits are their own signature and keep counting" {
    const TestState = struct {
        executed_steps: u64 = 0,
    };
    var predictor = Predictor{};
    var state = TestState{};

    state.executed_steps = 100;
    predictor.note(&state, .wait_timeout, 0x827CEC28, 0x7fff2080, true);
    state.executed_steps = 200;
    predictor.note(&state, .wait_timeout, 0x827CEC28, 0x7fff2080, true);
    state.executed_steps = 300;
    predictor.note(&state, .wait_timeout, 0x827CEC28, 0x7fff2080, true);

    const signature = predictor.findOrInsert(.wait_timeout, 0x827CEC28).?;
    try std.testing.expectEqual(@as(u32, 3), signature.count);
    try std.testing.expectEqual(@as(u64, 100), signature.first_seen_step);
    try std.testing.expectEqual(@as(u64, 300), signature.last_seen_step);
    // A timeout wait is a wait on a different op: distinct from a plain wait.
    try std.testing.expectEqual(@as(u32, 1), predictor.distinct_signatures);
}

test "distinct objects and operations stay distinct" {
    const TestState = struct {
        executed_steps: u64 = 0,
    };
    var predictor = Predictor{};
    var state = TestState{};

    predictor.note(&state, .wait, 0x1000, 0x7fff2110, true);
    predictor.note(&state, .wait, 0x2000, 0x7fff2110, true);
    predictor.note(&state, .set_event, 0x1000, 0x7fff2080, true);
    predictor.note(&state, .release_semaphore, 0x3000, 0x7fff2080, true);
    try std.testing.expectEqual(@as(u32, 4), predictor.distinct_signatures);

    // The same (op, object) accumulates, not splits.
    predictor.note(&state, .wait, 0x1000, 0x7fff2110, true);
    try std.testing.expectEqual(@as(u32, 4), predictor.distinct_signatures);
    try std.testing.expectEqual(@as(u32, 2), predictor.findOrInsert(.wait, 0x1000).?.count);
}

test "full-table eviction keeps the hottest wait signature" {
    const TestState = struct {
        executed_steps: u64 = 0,
    };
    var predictor = Predictor{};
    var state = TestState{};

    // Fill the table with distinct signatures.
    var i: u64 = 0;
    while (i < SIGNATURE_CAPACITY) : (i += 1) {
        predictor.note(&state, .wait, 0x1000 + i * 0x100, 0x7fff2110, false);
        state.executed_steps += 1;
    }
    try std.testing.expectEqual(@as(u32, @intCast(SIGNATURE_CAPACITY)), predictor.distinct_signatures);

    // Make the first signature hot.
    var j: u64 = 0;
    while (j < 8) : (j += 1) {
        predictor.note(&state, .wait, 0x1000, 0x7fff2110, false);
        state.executed_steps += 1;
    }
    try std.testing.expectEqual(@as(u32, 9), predictor.findOrInsert(.wait, 0x1000).?.count);

    // One more distinct signature evicts the least-used entry; the hot one
    // survives.
    predictor.note(&state, .release_semaphore, 0x9999, 0x7fff2080, false);
    try std.testing.expectEqual(@as(u32, @intCast(SIGNATURE_CAPACITY)), predictor.distinct_signatures);
    try std.testing.expectEqual(@as(u32, 9), predictor.findOrInsert(.wait, 0x1000).?.count);
}

test "recent ring wraps and reports the newest operations" {
    const TestState = struct {
        executed_steps: u64 = 0,
    };
    var predictor = Predictor{};
    var state = TestState{};

    var i: u64 = 0;
    while (i < RECENT_CAPACITY + 4) : (i += 1) {
        predictor.note(&state, .wait, 0x1000 + i, 0x7fff2110, false);
        state.executed_steps += 1;
    }
    try std.testing.expectEqual(@as(usize, RECENT_CAPACITY), predictor.recentCount());
    // The newest operation (index RECENT_CAPACITY+3) survives the wrap.
    const newest = predictor.recentChronological(RECENT_CAPACITY - 1).?;
    try std.testing.expectEqual(@as(u64, 0x1000 + (RECENT_CAPACITY + 3)), newest.object);
}

// A dump that reads as a list cannot say whether the run ended inside a
// livelock or inside a working pump, and those look identical in a list of
// repetition counts.
test "an empty predictor terminates quiet" {
    const TestState = struct { executed_steps: u64 = 0 };
    var predictor = Predictor{};
    var state = TestState{};
    try std.testing.expectEqual(Termination.quiet, predictor.dump(&state, "test"));
}

test "a mature retained signature with no audit to account for it is unaccounted" {
    const TestState = struct { executed_steps: u64 = 0 };
    var predictor = Predictor{};
    var state = TestState{};
    state.executed_steps = 100;
    var index: u32 = 0;
    while (index < MIN_CYCLE_COUNT) : (index += 1) {
        state.executed_steps = 100 + index;
        predictor.note(&state, .wait, 0x827CEC14, 0x7fff2110, true);
    }
    try std.testing.expectEqual(Termination.unaccounted_cycle, predictor.dump(&state, "test"));
}

test "signatures the wait audit accounts for terminate as healthy pumps" {
    const Classification = enum { expected_pump, expected_bounded, insufficient_evidence };
    const Subject = struct { object: u64 = 0 };
    const Audit = struct {
        subjects: [2]Subject = [_]Subject{.{}} ** 2,
        count: usize = 0,
        fn classify(self: *const @This(), subject: Subject, step: u64) Classification {
            _ = self;
            _ = step;
            return if (subject.object == 0x827CEC14) .expected_pump else .expected_bounded;
        }
    };
    const TestState = struct {
        executed_steps: u64 = 0,
        wait_audit: Audit = .{},
    };
    var predictor = Predictor{};
    var state = TestState{};
    state.wait_audit.subjects[0] = .{ .object = 0x827CEC14 };
    state.wait_audit.subjects[1] = .{ .object = 0x827CEC38 };
    state.wait_audit.count = 2;
    var index: u32 = 0;
    while (index < MIN_CYCLE_COUNT) : (index += 1) {
        state.executed_steps = 100 + index;
        predictor.note(&state, .wait, 0x827CEC14, 0x7fff2110, true);
        predictor.note(&state, .set_event, 0x827CEC38, 0x7fff2080, true);
    }
    try std.testing.expectEqual(Termination.healthy_pumps_only, predictor.dump(&state, "test"));
    // First sightings remain visible as breadcrumbs even when the audit already
    // knows the object is a healthy pump. Once recurrence is mature, the audit
    // classification suppresses the repeated detail without hiding its count.
    try std.testing.expect(predictor.suppressed >= 2);
    try std.testing.expectEqual(@as(u64, 2), predictor.emissions);
}

test "one unaccounted signature among healthy ones still terminates unaccounted" {
    const Classification = enum { expected_pump, expected_bounded, insufficient_evidence };
    const Subject = struct { object: u64 = 0 };
    const Audit = struct {
        subjects: [1]Subject = [_]Subject{.{}} ** 1,
        count: usize = 0,
        fn classify(self: *const @This(), subject: Subject, step: u64) Classification {
            _ = self;
            _ = subject;
            _ = step;
            return .expected_pump;
        }
    };
    const TestState = struct {
        executed_steps: u64 = 0,
        wait_audit: Audit = .{},
    };
    var predictor = Predictor{};
    var state = TestState{};
    state.wait_audit.subjects[0] = .{ .object = 0x827CEC14 };
    state.wait_audit.count = 1;
    state.executed_steps = 100;
    var index: u32 = 0;
    while (index < MIN_CYCLE_COUNT) : (index += 1) {
        state.executed_steps = 100 + index;
        predictor.note(&state, .wait, 0x827CEC14, 0x7fff2110, true);
        predictor.note(&state, .wait, 0x14D49FD0, 0x7fff2090, true);
    }
    try std.testing.expectEqual(Termination.unaccounted_cycle, predictor.dump(&state, "test"));
}
