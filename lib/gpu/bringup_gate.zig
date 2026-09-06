//! The one graphics report a reader should look at first: which boundary of
//! the console's display path was the first that a watched, eligible observer
//! never saw executed — and whether that zero belongs to the title or to
//! Rosette.
//!
//! ## The failure this replaces
//!
//! A seventeen-minute Halo 3 run on 2026-08-30 emitted, in one log file:
//!
//! * `preinit title ABSENT VdInitializeEngines ran — the title has not begun
//!   graphics bring-up at all`,
//! * `RING BUFFER: bootstrap failed: ring init handshake never completed`,
//! * `SWAP HEALTH: producer=never_started, the guest never wrote the ring
//!   write pointer`, and later
//! * `SWAP HEALTH: published=YES consumed_batch(dwords/packets/draws)=25/72/24`.
//!
//! All four were true statements about different moments and none of them was
//! retracted, so the log answered the question "did the title bring the GPU
//! up?" four different ways depending on which line was read. Underneath, an
//! instruction-pointer tracepoint had recorded `VdInitializeRingBuffer_entry`
//! entered at step 3_035_380_401 — a fact none of the four consulted.
//!
//! ## What this does differently
//!
//! Three rules, and they are the whole module:
//!
//! 1. **Only a crossing counts.** A boundary is crossed when the instruction
//!    pointer arrived at a resolved symbol. No log line, counter, memory scan
//!    or harness model can set a bit here.
//! 2. **Watched and crossed are separate masks.** A boundary nothing was
//!    observing is reported `UNWATCHED` and is never named as the frontier.
//!    "The title did not do this" and "Rosette did not look" are opposite
//!    findings and this is the only place in the graphics stack that keeps
//!    them apart structurally rather than by convention.
//! 3. **A repeating boundary that stopped is its own finding.** A vblank pump
//!    that fired four times in seventeen minutes reads `crossed=YES` on any
//!    once-only ledger. Cadence is in the contract precisely so that reading
//!    cannot happen here.
//!
//! ## What it deliberately does not do
//!
//! It never crosses a boundary on the guest's behalf, never infers a crossing
//! from a downstream effect, and never promotes a harness diagnostic into an
//! authentic crossing. A gate that could be satisfied by the harness would
//! turn the one unforgeable signal in the graphics stack into another claim.

const std = @import("std");
const contract = @import("xenia_gpu_bringup_contract");

pub const Boundary = contract.Boundary;
pub const Phase = contract.Phase;
pub const Owner = contract.Owner;
pub const Requirement = contract.Requirement;
pub const Cadence = contract.Cadence;
pub const boundary_count = contract.boundary_count;
pub const Mask = contract.Mask;

/// Every boundary in console order. Re-exported so the arming code in the
/// Mach-O processor works from the gate rather than reaching past it into the
/// package: the gate is the only thing that may decide a boundary was crossed,
/// and it should also be the only thing that decides what the set is.
pub const contractBoundaries = contract.allBoundaries;
pub const boundaryBit = contract.bit;
pub const maskHas = contract.isSet;

/// How long a repeating boundary may stay silent before the silence is
/// reported as a finding rather than as ordinary spacing between frames.
///
/// Sized against the observed rate: the run this was written for executed
/// about four million guest steps a second and produced a vblank roughly every
/// eight seconds of host time, so a hundred million steps is a little over
/// twenty seconds of run — long enough that several frames should have passed
/// at any healthy rate, short enough to name a stall inside one checkpoint.
pub const default_silence_budget: u64 = 100_000_000;

/// What a single boundary's observations add up to.
pub const State = enum(u8) {
    /// Nothing is watching. Every conclusion below this is Rosette's to fix,
    /// not the title's.
    unwatched,
    /// Watched, uncrossed, and its prerequisite was never crossed either. The
    /// run has not arrived here; this zero names nothing on its own.
    blocked_upstream,
    /// Watched, eligible, never crossed. This is an execution fact.
    never_crossed,
    /// Crossed, and either it only had to happen once, it is event-driven, or
    /// its autonomous pump is still going.
    crossed,
    /// Crossed and then silent past the budget, on a boundary that should keep
    /// repeating. The strongest finding this module produces, because it names
    /// a mechanism that worked and then stopped.
    stalled_after_crossing,
    /// Crossed, but the current source authority established that this
    /// boundary is diagnostic/host-only and cannot be used as a guest-output
    /// heartbeat. The crossing remains visible; only its silence is excluded
    /// from repeating-pump liveness.
    not_eligible,

    pub fn label(self: State) []const u8 {
        return switch (self) {
            .unwatched => "UNWATCHED",
            .blocked_upstream => "blocked-upstream",
            .never_crossed => "NEVER",
            .crossed => "crossed",
            .stalled_after_crossing => "STALLED",
            .not_eligible => "not-eligible",
        };
    }

    /// Whether this state is a finding a reader should act on, as opposed to a
    /// consequence of one.
    pub fn actionable(self: State) bool {
        return self == .never_crossed or self == .stalled_after_crossing or self == .unwatched;
    }
};

/// Everything retained about one boundary. Deliberately small and fixed: the
/// gate is consulted from the reporting path on every checkpoint and must not
/// allocate.
pub const Record = struct {
    watchers: u32 = 0,
    hits: u64 = 0,
    first_step: u64 = 0,
    last_step: u64 = 0,
    first_thread: u64 = 0,
    first_caller: u64 = 0,

    pub fn crossed(self: Record) bool {
        return self.hits != 0;
    }

    pub fn watched(self: Record) bool {
        return self.watchers != 0;
    }
};

/// Whether an armed tracepoint may make a monotone witness statement for one
/// boundary at the current checkpoint.
///
/// A positive crossing is always usable. A zero is usable only when the gate
/// says the boundary was eligible and never crossed; a downstream boundary in
/// `blocked_upstream` state has not been reached and must remain unobserved.
/// Keeping this decision beside the prerequisite state machine prevents report
/// code from turning a blocked zero into a false closed observation.
pub fn tracepointWitnessMayState(record: Record, state: State) bool {
    return record.crossed() or state == .never_crossed;
}

/// The single sentence a checkpoint leads with.
pub const Finding = enum(u8) {
    /// Nothing anywhere on the surface is being watched.
    blind,
    /// The frontier is a boundary nothing observes, so no negative claim below
    /// it is supportable.
    observer_hole,
    /// A repeating boundary crossed and stopped. Named ahead of any never-
    /// crossed boundary downstream of it, because a mechanism that stopped
    /// explains its own downstream zeroes and a never-crossed one does not.
    pump_stopped,
    /// A watched, eligible boundary was never crossed.
    boundary_never_crossed,
    /// A boundary was crossed while its prerequisite never was, so one of the
    /// two observations is wrong.
    inverted_order,
    /// Every required boundary was crossed and nothing has stalled.
    complete,

    pub fn label(self: Finding) []const u8 {
        return switch (self) {
            .blind => "blind",
            .observer_hole => "observer_hole",
            .pump_stopped => "pump_stopped",
            .boundary_never_crossed => "boundary_never_crossed",
            .inverted_order => "inverted_order",
            .complete => "complete",
        };
    }
};

pub const Verdict = struct {
    finding: Finding = .blind,
    /// The boundary the finding is about, when there is one.
    subject: ?Boundary = null,
    /// Total crossed, watched, and declared.
    crossed: u8 = 0,
    watched: u8 = 0,
    total: u8 = boundary_count,
    /// Boundaries that were watched, eligible and uncrossed. This is the
    /// number of real findings; every other zero is downstream of one of them.
    actionable: u8 = 0,
    /// Boundaries that are eligible and unwatched. Every one of these is a
    /// hole in Rosette rather than a fact about the title.
    holes: u8 = 0,
    inversions: u8 = 0,
    step: u64 = 0,

    pub fn owner(self: Verdict) ?Owner {
        const which = self.subject orelse return null;
        return which.owner();
    }

    pub fn phase(self: Verdict) ?Phase {
        const which = self.subject orelse return null;
        return which.phase();
    }

    /// The sentence that names what to do next. This is the deliverable: a
    /// table of states sends the next hour to whichever row was read first.
    pub fn describe(self: Verdict) []const u8 {
        return switch (self.finding) {
            .blind => "no graphics boundary is being watched at all, so every zero in every graphics report below is Rosette's and none of them is a statement about the title. Resolve the boundary symbols before reading anything else",
            .observer_hole => "the first boundary the run is eligible to cross has no observer, so nothing below it can be claimed either way. Arm it; until then this run cannot distinguish a title that stopped here from one that went past",
            .pump_stopped => "a boundary that must keep repeating crossed and then went silent. Every zero downstream of it is a consequence of this stall, not an independent failure — and the thing to find is what the stopped mechanism was waiting on, not what it failed to produce",
            .boundary_never_crossed => "the run reached this boundary's prerequisite and never crossed the boundary itself. This is an execution fact rather than a missing log line, and it is the only actionable gap upstream of everything else that reads zero",
            .inverted_order => "a boundary was crossed while the boundary that must precede it was not. This cannot happen on hardware, so one of the two readings is wrong — and it is the negative one, because a crossing is proof and an absence is only the absence of proof",
            .complete => "every required boundary was crossed and no repeating boundary has stalled. If nothing is on screen the gap is downstream of this contract",
        };
    }
};

/// The live ledger.
pub const Gate = struct {
    records: [boundary_count]Record = [_]Record{.{}} ** boundary_count,
    silence_budget: u64 = default_silence_budget,
    /// Repeating boundaries are eligible by default. Runtime provenance may
    /// clear a bit when a crossed boundary is backed only by Rosette
    /// diagnostics; that keeps diagnostic paint visible without turning it
    /// into a false guest-pump failure.
    repeating_liveness_eligibility: Mask = std.math.maxInt(Mask),
    /// Set once the boundary set has been armed, so an empty gate reports
    /// `blind` rather than a frontier it never looked for.
    sealed: bool = false,

    pub fn recordFor(self: *const Gate, boundary: Boundary) Record {
        return self.records[@intFromEnum(boundary)];
    }

    /// Declare that `watchers` addresses are armed for a boundary. Additive:
    /// a boundary can be watched by a shim, a trampoline and two backend
    /// overrides, and how many is worth reporting because it changes how much
    /// a zero is worth.
    pub fn arm(self: *Gate, boundary: Boundary, watchers: u32) void {
        self.records[@intFromEnum(boundary)].watchers +|= watchers;
    }

    pub fn seal(self: *Gate) void {
        self.sealed = true;
    }

    pub fn setRepeatingLivenessEligible(self: *Gate, boundary: Boundary, eligible: bool) void {
        if (boundary.cadence() != .repeating) return;
        const bit = contract.bit(boundary);
        if (eligible) {
            self.repeating_liveness_eligibility |= bit;
        } else {
            self.repeating_liveness_eligibility &= ~bit;
        }
    }

    pub fn repeatingLivenessEligible(self: *const Gate, boundary: Boundary) bool {
        return boundary.cadence() != .repeating or
            contract.isSet(self.repeating_liveness_eligibility, boundary);
    }

    /// Record a crossing. `hits` is the total observed for this boundary
    /// across every address armed for it, so this is idempotent under repeated
    /// synchronisation from the tracepoint set rather than incremental.
    pub fn observe(
        self: *Gate,
        boundary: Boundary,
        hits: u64,
        first_step: u64,
        last_step: u64,
        first_thread: u64,
        first_caller: u64,
    ) void {
        const slot = &self.records[@intFromEnum(boundary)];
        if (hits == 0) return;
        if (slot.hits == 0 or first_step < slot.first_step) {
            slot.first_step = first_step;
            slot.first_thread = first_thread;
            slot.first_caller = first_caller;
        }
        if (last_step > slot.last_step) slot.last_step = last_step;
        if (hits > slot.hits) slot.hits = hits;
    }

    pub fn crossedMask(self: *const Gate) contract.Mask {
        var mask: contract.Mask = 0;
        for (contract.allBoundaries()) |boundary| {
            if (self.records[@intFromEnum(boundary)].crossed()) mask |= contract.bit(boundary);
        }
        return mask;
    }

    /// How many distinct boundaries have ever been crossed.
    ///
    /// Monotone by construction — a boundary never un-crosses — and it only
    /// rises because the guest called something it had not called before. That
    /// makes it usable as a progress axis a stopped guest cannot advance,
    /// which a hit count would not be: a spin can raise a hit count.
    pub fn crossedCount(self: *const Gate) u64 {
        var total: u64 = 0;
        for (contract.allBoundaries()) |boundary| {
            if (self.records[@intFromEnum(boundary)].crossed()) total += 1;
        }
        return total;
    }

    pub fn watchedMask(self: *const Gate) contract.Mask {
        var mask: contract.Mask = 0;
        for (contract.allBoundaries()) |boundary| {
            if (self.records[@intFromEnum(boundary)].watched()) mask |= contract.bit(boundary);
        }
        return mask;
    }

    /// How long a boundary has been silent at `step`. Zero for a boundary that
    /// never crossed: silence is only meaningful after a first crossing, and
    /// reporting a never-crossed boundary as "silent for the whole run" is how
    /// a stall verdict gets attached to something that never started.
    pub fn quietFor(self: *const Gate, boundary: Boundary, step: u64) u64 {
        const slot = self.records[@intFromEnum(boundary)];
        if (!slot.crossed()) return 0;
        if (step <= slot.last_step) return 0;
        return step - slot.last_step;
    }

    pub fn state(self: *const Gate, boundary: Boundary, step: u64) State {
        const slot = self.records[@intFromEnum(boundary)];
        if (!slot.watched()) return .unwatched;
        if (slot.crossed()) {
            if (boundary.cadence() == .repeating and
                !self.repeatingLivenessEligible(boundary))
            {
                return .not_eligible;
            }
            if (boundary.cadence() == .repeating and
                self.quietFor(boundary, step) > self.silence_budget)
            {
                return .stalled_after_crossing;
            }
            return .crossed;
        }
        if (boundary.prerequisite()) |earlier| {
            if (!self.records[@intFromEnum(earlier)].crossed()) return .blocked_upstream;
        }
        return .never_crossed;
    }

    /// The first repeating boundary that crossed and then stopped, in console
    /// order. Reported ahead of any never-crossed boundary downstream of it:
    /// a mechanism that stopped explains its own downstream zeroes.
    pub fn firstStalled(self: *const Gate, step: u64) ?Boundary {
        for (contract.allBoundaries()) |boundary| {
            if (self.state(boundary, step) == .stalled_after_crossing) return boundary;
        }
        return null;
    }

    /// The boundary this gate's verdict names, when it names one.
    ///
    /// Exposed separately from `verdict` because the frontier is consumed by
    /// gates that only need the subject, and re-deriving it at each call site
    /// is how two consumers end up naming different boundaries.
    pub fn frontier(self: *const Gate, step: u64) ?Boundary {
        return self.verdict(step).subject;
    }

    pub fn verdict(self: *const Gate, step: u64) Verdict {
        var out = Verdict{ .step = step };
        for (contract.allBoundaries()) |boundary| {
            const slot = self.records[@intFromEnum(boundary)];
            if (slot.watched()) out.watched += 1;
            if (slot.crossed()) out.crossed += 1;
        }
        const crossed = self.crossedMask();
        const watched = self.watchedMask();
        const live = contract.actionable(crossed, watched);
        for (contract.allBoundaries()) |boundary| {
            if (contract.isSet(live, boundary) and boundary.requirement() != .optional) {
                out.actionable += 1;
            }
        }
        const inverted = contract.inversions(crossed);
        for (contract.allBoundaries()) |boundary| {
            if (contract.isSet(inverted, boundary)) out.inversions += 1;
        }
        var hole_cursor: ?Boundary = null;
        for (contract.allBoundaries()) |boundary| {
            if (slotEligibleUnwatched(self, boundary, crossed)) {
                out.holes += 1;
                if (hole_cursor == null and boundary.requirement() != .optional) {
                    hole_cursor = boundary;
                }
            }
        }

        if (out.watched == 0) {
            out.finding = .blind;
            return out;
        }
        // Ordering of findings is the judgement this module makes. A pump that
        // stopped outranks a boundary that never ran, because the stopped pump
        // is why the later boundary never ran. An inversion outranks both,
        // because it says an observation is wrong and every ranking below it
        // is computed from observations.
        if (out.inversions != 0) {
            out.finding = .inverted_order;
            for (contract.allBoundaries()) |boundary| {
                if (contract.isSet(inverted, boundary)) {
                    out.subject = boundary;
                    break;
                }
            }
            return out;
        }
        if (self.firstStalled(step)) |stalled| {
            out.finding = .pump_stopped;
            out.subject = stalled;
            return out;
        }
        if (contract.frontier(crossed, watched)) |first| {
            // An observer hole strictly upstream of the frontier makes the
            // frontier unsupportable: the run may have gone past it through
            // the unwatched boundary without anything noticing.
            if (hole_cursor) |hole| {
                if (@intFromEnum(hole) < @intFromEnum(first)) {
                    out.finding = .observer_hole;
                    out.subject = hole;
                    return out;
                }
            }
            out.finding = .boundary_never_crossed;
            out.subject = first;
            return out;
        }
        if (hole_cursor) |hole| {
            out.finding = .observer_hole;
            out.subject = hole;
            return out;
        }
        out.finding = .complete;
        return out;
    }

    pub fn phaseProgress(self: *const Gate, which: Phase) contract.PhaseProgress {
        return contract.phaseProgress(which, self.crossedMask(), self.watchedMask());
    }
};

fn slotEligibleUnwatched(self: *const Gate, boundary: Boundary, crossed: contract.Mask) bool {
    if (self.records[@intFromEnum(boundary)].watched()) return false;
    if (contract.isSet(crossed, boundary)) return false;
    if (boundary.prerequisite()) |earlier| {
        if (!contract.isSet(crossed, earlier)) return false;
    }
    return true;
}

fn fullyArmed() Gate {
    var gate = Gate{};
    for (contract.allBoundaries()) |boundary| gate.arm(boundary, 1);
    gate.seal();
    return gate;
}

test "an unarmed gate reports blind rather than a frontier" {
    const gate = Gate{};
    const out = gate.verdict(1_000);
    try std.testing.expectEqual(Finding.blind, out.finding);
    try std.testing.expect(out.subject == null);
}

// The distinction the module exists for.
test "an unwatched boundary is a hole in Rosette, not a fact about the title" {
    var gate = Gate{};
    gate.arm(.query_video_mode, 1);
    gate.arm(.initialize_ring_buffer, 2);
    gate.seal();
    gate.observe(.query_video_mode, 1, 10, 10, 0xaa, 0xbb);

    const out = gate.verdict(1_000);
    try std.testing.expectEqual(Finding.observer_hole, out.finding);
    try std.testing.expectEqual(Boundary.initialize_engines, out.subject.?);
    try std.testing.expectEqual(State.unwatched, gate.state(.initialize_engines, 1_000));
}

test "a watched eligible boundary that never ran is the frontier" {
    var gate = fullyArmed();
    gate.observe(.query_video_mode, 1, 10, 10, 0xaa, 0);
    gate.observe(.initialize_engines, 1, 20, 20, 0xaa, 0);
    const out = gate.verdict(1_000);
    try std.testing.expectEqual(Finding.boundary_never_crossed, out.finding);
    try std.testing.expectEqual(Boundary.set_interrupt_callback, out.subject.?);
    try std.testing.expectEqual(Owner.guest_title, out.owner().?);
    try std.testing.expectEqual(Phase.bringup, out.phase().?);
}

// The reading this module was written for: a pump that fired four times in a
// seventeen-minute run and then stopped reads `crossed=YES` on a once-only
// ledger, and `crossed=YES` is what sends the next hour downstream of it.
test "an autonomous pump that crossed and went quiet outranks a later zero" {
    var gate = fullyArmed();
    for ([_]Boundary{
        .query_video_mode,
        .initialize_engines,
        .set_interrupt_callback,
        .initialize_ring_buffer,
        .enable_rptr_write_back,
        .system_command_buffer_query,
    }) |boundary| gate.observe(boundary, 1, 100, 100, 0xaa, 0);

    gate.observe(.mark_vblank, 4, 200, 974_046_863, 0xcc, 0);
    gate.observe(.write_pointer_updated, 2, 3_397_449_143, 3_407_441_654, 0xdd, 0);
    gate.observe(.command_processor_worker_running, 1, 3_300_000_000, 4_999_000_000, 0xee, 0);
    gate.observe(.execute_primary_buffer, 1, 3_397_523_080, 3_397_523_080, 0xee, 0);
    gate.observe(.execute_packet_type3, 72, 3_397_523_090, 3_407_000_000, 0xee, 0);
    gate.observe(.issue_draw, 24, 3_397_600_000, 3_406_000_000, 0xee, 0);

    const out = gate.verdict(5_000_000_000);
    try std.testing.expectEqual(Finding.pump_stopped, out.finding);
    // Publication, command consumption and draws are event-driven: their
    // silence after the batch drained cannot outrank the vblank pump that
    // actually owns an autonomous cadence.
    try std.testing.expectEqual(Boundary.mark_vblank, out.subject.?);
    try std.testing.expectEqual(
        State.stalled_after_crossing,
        gate.state(.mark_vblank, 5_000_000_000),
    );
}

test "silence is only measured after a first crossing" {
    var gate = fullyArmed();
    try std.testing.expectEqual(@as(u64, 0), gate.quietFor(.mark_vblank, 5_000_000_000));
    try std.testing.expectEqual(State.never_crossed, gate.state(.mark_vblank, 5_000_000_000));
    gate.observe(.mark_vblank, 1, 100, 100, 0, 0);
    try std.testing.expectEqual(@as(u64, 4_999_999_900), gate.quietFor(.mark_vblank, 5_000_000_000));
}

test "diagnostic paint is event driven and silence is never a pump fault" {
    var gate = fullyArmed();
    gate.observe(.host_paint, 5, 100, 200, 0, 0);
    gate.setRepeatingLivenessEligible(.host_paint, false);

    try std.testing.expectEqual(Cadence.event_driven, Boundary.host_paint.cadence());
    try std.testing.expect(gate.repeatingLivenessEligible(.host_paint));
    try std.testing.expectEqual(State.crossed, gate.state(.host_paint, 5_000_000_000));
    try std.testing.expect(gate.firstStalled(5_000_000_000) == null);
}

test "a drained command batch cannot manufacture a pump stall" {
    var gate = fullyArmed();
    gate.observe(.write_pointer_updated, 2, 100, 200, 0, 0);
    gate.observe(.execute_primary_buffer, 2, 110, 210, 0, 0);
    gate.observe(.execute_packet_type3, 63, 120, 220, 0, 0);
    gate.observe(.issue_draw, 24, 130, 230, 0, 0);

    const much_later: u64 = 5_000_000_000;
    try std.testing.expectEqual(State.crossed, gate.state(.write_pointer_updated, much_later));
    try std.testing.expectEqual(State.crossed, gate.state(.execute_packet_type3, much_later));
    try std.testing.expectEqual(State.crossed, gate.state(.issue_draw, much_later));
    try std.testing.expect(gate.firstStalled(much_later) == null);
}

test "a crossing without its prerequisite is reported as an inversion first" {
    var gate = fullyArmed();
    gate.observe(.initialize_ring_buffer, 1, 100, 100, 0, 0);
    const out = gate.verdict(200);
    try std.testing.expectEqual(Finding.inverted_order, out.finding);
    try std.testing.expectEqual(Boundary.initialize_ring_buffer, out.subject.?);
}

test "downstream zeroes are blocked upstream rather than actionable" {
    var gate = fullyArmed();
    gate.observe(.query_video_mode, 1, 10, 10, 0, 0);
    gate.observe(.initialize_engines, 1, 20, 20, 0, 0);
    try std.testing.expectEqual(State.blocked_upstream, gate.state(.execute_primary_buffer, 100));
    try std.testing.expectEqual(State.blocked_upstream, gate.state(.issue_swap, 100));
    const out = gate.verdict(100);
    // Only the eligible uncrossed boundaries count as findings: the whole
    // presentation phase is downstream of one of them and carries none.
    try std.testing.expect(out.actionable < 10);
}

test "blocked tracepoint zeroes do not become monotone witness statements" {
    const empty = Record{};
    try std.testing.expect(tracepointWitnessMayState(empty, .never_crossed));
    try std.testing.expect(!tracepointWitnessMayState(empty, .blocked_upstream));
    try std.testing.expect(!tracepointWitnessMayState(empty, .unwatched));
    try std.testing.expect(tracepointWitnessMayState(.{ .hits = 1 }, .crossed));
    // A positive crossing remains evidence even when a repeating source has
    // been excluded from silence accounting.
    try std.testing.expect(tracepointWitnessMayState(.{ .hits = 1 }, .not_eligible));
}

test "observations are idempotent under repeated synchronisation" {
    var gate = fullyArmed();
    gate.observe(.mark_vblank, 4, 200, 900, 0xcc, 0);
    gate.observe(.mark_vblank, 4, 200, 900, 0xcc, 0);
    const slot = gate.recordFor(.mark_vblank);
    try std.testing.expectEqual(@as(u64, 4), slot.hits);
    try std.testing.expectEqual(@as(u64, 200), slot.first_step);
    try std.testing.expectEqual(@as(u64, 900), slot.last_step);
}

test "a complete surface reports complete" {
    var gate = fullyArmed();
    for (contract.allBoundaries()) |boundary| {
        gate.observe(boundary, 10, 100, 4_999_999_999, 0, 0);
    }
    const out = gate.verdict(5_000_000_000);
    try std.testing.expectEqual(Finding.complete, out.finding);
    try std.testing.expectEqual(@as(u8, 0), out.holes);
}

test "phase progress separates blind phases from unreached ones" {
    var gate = Gate{};
    for (contract.phaseBoundaries(.bringup)) |boundary| gate.arm(boundary, 1);
    gate.seal();
    try std.testing.expect(!gate.phaseProgress(.bringup).blind());
    try std.testing.expect(gate.phaseProgress(.presentation).blind());
}

// A boundary count is usable as a progress axis only if a spin cannot raise
// it. Hits can be spun; distinct crossings cannot.
test "the crossed count rises only when a new boundary is reached" {
    var gate = Gate{};
    try std.testing.expectEqual(@as(u64, 0), gate.crossedCount());

    gate.observe(.initialize_engines, 1, 100, 100, 0, 0);
    try std.testing.expectEqual(@as(u64, 1), gate.crossedCount());

    // A thousand more hits on the same boundary is the same one boundary.
    gate.observe(.initialize_engines, 1000, 100, 5000, 0, 0);
    try std.testing.expectEqual(@as(u64, 1), gate.crossedCount());

    gate.observe(.initialize_ring_buffer, 1, 200, 200, 0, 0);
    try std.testing.expectEqual(@as(u64, 2), gate.crossedCount());
    try std.testing.expect(gate.crossedCount() <= boundary_count);
}
