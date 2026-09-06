//! Which observer to believe when the graphics reports disagree with each
//! other, and why the run's own log kept answering one question four ways.
//!
//! ## The reading this was written against
//!
//! A single Halo 3 log from 2026-08-30 contains all of these:
//!
//! | claim | said | by |
//! |---|---|---|
//! | ring initialised | **NO** | emulator bootstrap gate, at 2303 ms |
//! | ring initialised | **YES** | tracepoint at `VdInitializeRingBuffer_entry`, step 3 035 380 401 |
//! | draws submitted | **24** | Rosette's scan of ring memory |
//! | write pointer written | **0** | emulator's own applied-update counter |
//! | GPU pre-initialisation | **12/13 established** | Rosette's ladder |
//! | `vd_init_engines` | **0** | emulator's own counter |
//!
//! Nobody was lying. The bootstrap gate looked before the title arrived; the
//! ring scan read bytes that resembled packets; the ladder counted rungs whose
//! evidence came from whichever observer answered first. What was missing was
//! any rule for ranking them, so every downstream report picked a side by
//! accident and the reader picked one by scrolling.
//!
//! ## The rules
//!
//! **1. Proof outranks absence of proof.** A positive observation is a thing
//! that happened. A negative one is only the statement that a particular
//! observer did not see it — which is worth very different amounts depending
//! on the observer. So a positive at any tier is believed over a negative at
//! any tier, and the conflict is reported rather than resolved silently.
//!
//! **2. A negative taken before the positive is stale, not contradictory.**
//! This is the rule the bootstrap gate needed. "Ring not initialised at
//! 2303 ms" and "ring initialised at step 3 035 380 401" are both true and
//! only one of them is current. Ranking them as a live conflict would burn the
//! reader's attention on a disagreement that does not exist.
//!
//! **3. A weak positive contested by a strong negative is unsubstantiated.**
//! If a memory scan claims a swap packet and an armed tracepoint at the
//! decoder says the decoder never ran, the scan found a byte pattern. Believe
//! the instruction pointer.
//!
//! **4. An absence seen only by a weak observer supports nothing.** "The log
//! never printed `VdSwap(`" is not evidence that `VdSwap` never ran; it is
//! evidence about the log. Reports built on that distinction is how this
//! investigation spent three passes downstream of a boundary nobody had
//! confirmed.
//!
//! The module holds no opinion about what the subjects mean. It ranks claims
//! and names conflicts; the graphics reports decide what to do about them.

const std = @import("std");

/// How much a claim is worth, strongest first. The ordinal *is* the strength,
/// so comparisons are integer comparisons and a new tier must be inserted in
/// the right place rather than appended.
pub const Tier = enum(u8) {
    /// The instruction pointer arrived at a resolved symbol. Nothing in the
    /// system can forge this: not a harness, not a log level, not a byte
    /// pattern.
    instruction_pointer = 0,
    /// A register aperture write, or a value read out of the emulator's own
    /// state after it applied it. The emulator acted on this, so it is a fact
    /// about behaviour rather than about logging.
    applied_state = 1,
    /// A counter the emulator increments in the same code path that does the
    /// work.
    emulator_counter = 2,
    /// A line the emulator printed. Its logging ran; its state machine may not
    /// have. Two different code paths, and the log is the one that never
    /// asserts.
    emulator_log_claim = 3,
    /// Rosette found a pattern in guest memory that matches what it was
    /// looking for. Uninitialised memory matches a great many patterns.
    memory_scan = 4,
    /// A Rosette model, a retained batch, or a substitution layer. Useful for
    /// keeping a run moving and worthless as evidence about the title.
    rosette_model = 5,

    pub fn label(self: Tier) []const u8 {
        return switch (self) {
            .instruction_pointer => "instruction-pointer",
            .applied_state => "applied-state",
            .emulator_counter => "emulator-counter",
            .emulator_log_claim => "emulator-log-claim",
            .memory_scan => "memory-scan",
            .rosette_model => "rosette-model",
        };
    }

    pub fn strongerThan(self: Tier, other: Tier) bool {
        return @intFromEnum(self) < @intFromEnum(other);
    }

    /// Whether this observer's *failure to see* something is worth anything.
    /// A tracepoint that never fired is an execution fact. A log line that
    /// never appeared is a fact about logging.
    pub fn absenceIsEvidence(self: Tier) bool {
        return switch (self) {
            .instruction_pointer, .applied_state, .emulator_counter => true,
            .emulator_log_claim, .memory_scan, .rosette_model => false,
        };
    }
};

/// The graphics facts that more than one observer claims, and that the reports
/// have historically disagreed about. Deliberately not the whole pipeline:
/// a subject earns a place here by having been contradicted.
pub const Subject = enum(u8) {
    gpu_engines_initialized,
    interrupt_callback_registered,
    interrupt_callback_entered_guest,
    vblank_pump_live,
    ring_initialized,
    ring_write_pointer_published,
    command_processor_running,
    pm4_packets_consumed,
    render_target_programmed,
    draws_issued,
    swap_requested_by_title,
    swap_packet_decoded,
    front_buffer_known,
    guest_frame_presented,

    pub fn label(self: Subject) []const u8 {
        return switch (self) {
            .gpu_engines_initialized => "GPU engines initialised",
            .interrupt_callback_registered => "graphics interrupt callback registered",
            .interrupt_callback_entered_guest => "graphics interrupt entered the guest",
            .vblank_pump_live => "vblank pump live",
            .ring_initialized => "command ring initialised",
            .ring_write_pointer_published => "ring write pointer published",
            .command_processor_running => "command processor running",
            .pm4_packets_consumed => "PM4 packets consumed",
            .render_target_programmed => "render target programmed",
            .draws_issued => "draws issued",
            .swap_requested_by_title => "swap requested by the title",
            .swap_packet_decoded => "swap packet decoded",
            .front_buffer_known => "front buffer address known",
            .guest_frame_presented => "guest frame presented",
        };
    }
};

pub const subject_count: usize = @typeInfo(Subject).@"enum".fields.len;

/// One observation, from one observer, at one moment.
pub const Claim = struct {
    tier: Tier = .rosette_model,
    /// Borrowed. Observer names are string literals owned by the reporting
    /// code, which outlives every run.
    observer: []const u8 = "",
    step: u64 = 0,
    /// The observer's own number, when it has one — packets, draws, hits.
    /// Carried so a conflict can print both magnitudes, which is usually where
    /// the answer is.
    magnitude: u64 = 0,
    present: bool = false,

    pub fn valid(self: Claim) bool {
        return self.observer.len != 0;
    }
};

/// What the ledger concluded for one subject.
pub const Standing = enum(u8) {
    /// No observer has said anything.
    unobserved,
    /// A positive claim, uncontested by any stronger observer.
    established,
    /// A positive claim that a stronger observer, looking later, did not see.
    /// The weak positive is not believed and the conflict is the finding.
    contested,
    /// Only negatives, and at least one of them from an observer whose absence
    /// is evidence.
    refuted,
    /// Only negatives, all from observers whose absence proves nothing.
    unsupported_absence,

    pub fn label(self: Standing) []const u8 {
        return switch (self) {
            .unobserved => "UNOBSERVED",
            .established => "established",
            .contested => "CONTESTED",
            .refuted => "refuted",
            .unsupported_absence => "UNSUPPORTED-ABSENCE",
        };
    }

    pub fn describe(self: Standing) []const u8 {
        return switch (self) {
            .unobserved => "nothing has looked at this, so neither a yes nor a no below it is supportable",
            .established => "a positive observation stands and no stronger observer looking later has failed to see it",
            .contested => "a weaker observer claims this and a stronger one, looking later, did not see it. Believe the stronger one: the weaker claim is a pattern that resembles the fact, not the fact",
            .refuted => "an observer whose absence is evidence looked and did not see it. This is an execution fact",
            .unsupported_absence => "the only observers reporting absence are ones whose silence proves nothing. This zero is about the observer, not the title",
        };
    }

    /// Whether a reader may build on this as a yes.
    pub fn believable(self: Standing) bool {
        return self == .established;
    }
};

pub const Finding = struct {
    subject: Subject,
    standing: Standing,
    /// The claim that decided the standing.
    authority: Claim = .{},
    /// The claim that contests it, when there is one.
    challenger: Claim = .{},
    /// Negatives that were taken before the authority's positive. Counted, not
    /// listed: they are the bootstrap gate looking before the title arrived,
    /// and every one of them is stale rather than wrong.
    stale_negatives: u16 = 0,
    /// How many distinct observers spoke about this subject at all.
    observers: u16 = 0,
};

const Slot = struct {
    positive: Claim = .{},
    negative: Claim = .{},
    /// The newest negative, which may be weaker than `negative` but later.
    /// Kept because staleness is about time and strength is about tier, and
    /// resolving one with the other is how a live conflict gets dismissed.
    newest_negative: Claim = .{},
    stale_negatives: u16 = 0,
    observers: u16 = 0,
};

pub const Ledger = struct {
    slots: [subject_count]Slot = [_]Slot{.{}} ** subject_count,
    /// Every claim offered, so a report can say how much was weighed.
    claims: u64 = 0,

    /// Offer an observation. Repeated offers from the same observer are
    /// expected — the reporting path re-synchronises on every checkpoint — and
    /// a later offer only replaces an earlier one when it is stronger, or
    /// equally strong and more recent.
    pub fn observe(self: *Ledger, subject: Subject, claim: Claim) void {
        if (!claim.valid()) return;
        self.claims +|= 1;
        const slot = &self.slots[@intFromEnum(subject)];
        slot.observers +|= 1;
        if (claim.present) {
            if (!slot.positive.valid() or
                claim.tier.strongerThan(slot.positive.tier) or
                (claim.tier == slot.positive.tier and claim.step < slot.positive.step))
            {
                // The *earliest* positive at the strongest tier is retained.
                // A crossing is proof, and the first one is when it happened;
                // a later one from the same observer says nothing new.
                slot.positive = claim;
            }
            return;
        }
        if (!slot.negative.valid() or claim.tier.strongerThan(slot.negative.tier)) {
            slot.negative = claim;
        }
        if (!slot.newest_negative.valid() or claim.step >= slot.newest_negative.step) {
            slot.newest_negative = claim;
        }
    }

    pub fn finding(self: *const Ledger, subject: Subject) Finding {
        const slot = self.slots[@intFromEnum(subject)];
        var out = Finding{
            .subject = subject,
            .standing = .unobserved,
            .observers = slot.observers,
        };
        if (!slot.positive.valid() and !slot.negative.valid()) return out;

        if (slot.positive.valid()) {
            out.authority = slot.positive;
            out.standing = .established;
            // Rule 2: a negative recorded before the positive is stale. Only a
            // stronger observer that looked *after* the crossing and still saw
            // nothing is a live contest.
            if (slot.negative.valid()) {
                if (slot.negative.step < slot.positive.step) {
                    out.stale_negatives +|= 1;
                } else if (slot.negative.tier.strongerThan(slot.positive.tier)) {
                    out.standing = .contested;
                    out.challenger = slot.negative;
                }
            }
            if (slot.newest_negative.valid() and
                slot.newest_negative.step < slot.positive.step and
                !std.mem.eql(u8, slot.newest_negative.observer, slot.negative.observer))
            {
                out.stale_negatives +|= 1;
            }
            return out;
        }

        out.authority = slot.negative;
        out.standing = if (slot.negative.tier.absenceIsEvidence())
            .refuted
        else
            .unsupported_absence;
        return out;
    }

    /// Subjects whose reported state cannot be built on: a weak positive a
    /// stronger observer denies, or an absence only weak observers noticed.
    /// This count is the honest measure of how much of the graphics report is
    /// load-bearing.
    pub fn unsafeSubjects(self: *const Ledger) u8 {
        var total: u8 = 0;
        inline for (@typeInfo(Subject).@"enum".fields) |field| {
            const subject: Subject = @enumFromInt(field.value);
            const found = self.finding(subject);
            if (found.standing == .contested or found.standing == .unsupported_absence) {
                total += 1;
            }
        }
        return total;
    }

    pub fn establishedSubjects(self: *const Ledger) u8 {
        var total: u8 = 0;
        inline for (@typeInfo(Subject).@"enum".fields) |field| {
            const subject: Subject = @enumFromInt(field.value);
            if (self.finding(subject).standing == .established) total += 1;
        }
        return total;
    }

    /// Live conflicts only: a stronger observer looking later than a weaker
    /// one's positive and not seeing it. Stale disagreements are excluded on
    /// purpose — a run that prints twenty of those has twenty ways to waste an
    /// hour and no findings.
    pub fn conflicts(self: *const Ledger) u8 {
        var total: u8 = 0;
        inline for (@typeInfo(Subject).@"enum".fields) |field| {
            const subject: Subject = @enumFromInt(field.value);
            if (self.finding(subject).standing == .contested) total += 1;
        }
        return total;
    }

    /// Negatives that were recorded before the crossing they appear to
    /// contradict. Reported as a count so a reader knows how much of the log's
    /// disagreement is a timing artefact and can stop re-litigating it.
    pub fn staleClaims(self: *const Ledger) u16 {
        var total: u16 = 0;
        inline for (@typeInfo(Subject).@"enum".fields) |field| {
            total +|= self.finding(@as(Subject, @enumFromInt(field.value))).stale_negatives;
        }
        return total;
    }
};

test "tier strength is the declaration order" {
    try std.testing.expect(Tier.instruction_pointer.strongerThan(.emulator_counter));
    try std.testing.expect(Tier.emulator_counter.strongerThan(.emulator_log_claim));
    try std.testing.expect(Tier.emulator_log_claim.strongerThan(.memory_scan));
    try std.testing.expect(!Tier.rosette_model.strongerThan(.memory_scan));
}

test "only strong observers make absence evidence" {
    try std.testing.expect(Tier.instruction_pointer.absenceIsEvidence());
    try std.testing.expect(!Tier.emulator_log_claim.absenceIsEvidence());
    try std.testing.expect(!Tier.memory_scan.absenceIsEvidence());
}

// Rule 2, and the reason this module exists. The emulator's bootstrap gate
// declared the ring uninitialised at 2303 ms; the tracepoint recorded
// VdInitializeRingBuffer_entry at step 3 035 380 401. Both true, one current.
test "a negative taken before the positive is stale rather than contradictory" {
    var ledger = Ledger{};
    ledger.observe(.ring_initialized, .{
        .tier = .emulator_log_claim,
        .observer = "xenia-bootstrap-gate",
        .step = 2_300_000_000,
        .present = false,
    });
    ledger.observe(.ring_initialized, .{
        .tier = .instruction_pointer,
        .observer = "tracepoint:VdInitializeRingBuffer_entry",
        .step = 3_035_380_401,
        .present = true,
    });
    const found = ledger.finding(.ring_initialized);
    try std.testing.expectEqual(Standing.established, found.standing);
    try std.testing.expectEqual(Tier.instruction_pointer, found.authority.tier);
    try std.testing.expectEqual(@as(u16, 1), found.stale_negatives);
    try std.testing.expectEqual(@as(u8, 0), ledger.conflicts());
}

// Rule 3. A ring scan that finds bytes resembling a swap packet, against a
// tracepoint at the decoder that says the decoder never ran.
test "a weak positive a stronger later observer denies is contested" {
    var ledger = Ledger{};
    ledger.observe(.swap_packet_decoded, .{
        .tier = .memory_scan,
        .observer = "ring-memory-scan",
        .step = 3_400_000_000,
        .magnitude = 1,
        .present = true,
    });
    ledger.observe(.swap_packet_decoded, .{
        .tier = .instruction_pointer,
        .observer = "tracepoint:ExecutePacketType3_XE_SWAP",
        .step = 5_000_000_000,
        .present = false,
    });
    const found = ledger.finding(.swap_packet_decoded);
    try std.testing.expectEqual(Standing.contested, found.standing);
    try std.testing.expectEqualStrings("ring-memory-scan", found.authority.observer);
    try std.testing.expectEqualStrings(
        "tracepoint:ExecutePacketType3_XE_SWAP",
        found.challenger.observer,
    );
    try std.testing.expect(!found.standing.believable());
    try std.testing.expectEqual(@as(u8, 1), ledger.conflicts());
}

// Rule 4. "The log never printed VdSwap(" is a fact about the log.
test "an absence only a log noticed supports nothing" {
    var ledger = Ledger{};
    ledger.observe(.swap_requested_by_title, .{
        .tier = .emulator_log_claim,
        .observer = "guest-log-breadcrumb",
        .step = 5_000_000_000,
        .present = false,
    });
    const found = ledger.finding(.swap_requested_by_title);
    try std.testing.expectEqual(Standing.unsupported_absence, found.standing);
    try std.testing.expectEqual(@as(u8, 1), ledger.unsafeSubjects());
}

test "an absence a tracepoint noticed is an execution fact" {
    var ledger = Ledger{};
    ledger.observe(.swap_requested_by_title, .{
        .tier = .instruction_pointer,
        .observer = "tracepoint:VdSwap_entry",
        .step = 5_000_000_000,
        .present = false,
    });
    try std.testing.expectEqual(Standing.refuted, ledger.finding(.swap_requested_by_title).standing);
    try std.testing.expectEqual(@as(u8, 0), ledger.unsafeSubjects());
}

test "an unobserved subject says nothing either way" {
    const ledger = Ledger{};
    const found = ledger.finding(.front_buffer_known);
    try std.testing.expectEqual(Standing.unobserved, found.standing);
    try std.testing.expect(!found.standing.believable());
}

// The reporting path re-synchronises every checkpoint, so a stable claim is
// offered hundreds of times and must not drift.
test "repeated offers keep the earliest crossing at the strongest tier" {
    var ledger = Ledger{};
    var step: u64 = 1_000;
    while (step <= 5_000) : (step += 1_000) {
        ledger.observe(.draws_issued, .{
            .tier = .instruction_pointer,
            .observer = "tracepoint:IssueDraw",
            .step = step,
            .magnitude = step,
            .present = true,
        });
    }
    const found = ledger.finding(.draws_issued);
    try std.testing.expectEqual(@as(u64, 1_000), found.authority.step);
    try std.testing.expectEqual(Standing.established, found.standing);
}

test "a stronger positive replaces a weaker one" {
    var ledger = Ledger{};
    ledger.observe(.pm4_packets_consumed, .{
        .tier = .memory_scan,
        .observer = "ring-payload",
        .step = 10,
        .magnitude = 72,
        .present = true,
    });
    ledger.observe(.pm4_packets_consumed, .{
        .tier = .instruction_pointer,
        .observer = "tracepoint:ExecutePacketType3",
        .step = 20,
        .magnitude = 72,
        .present = true,
    });
    const found = ledger.finding(.pm4_packets_consumed);
    try std.testing.expectEqual(Tier.instruction_pointer, found.authority.tier);
}

test "established and unsafe counts partition what a reader may build on" {
    var ledger = Ledger{};
    ledger.observe(.ring_initialized, .{
        .tier = .instruction_pointer,
        .observer = "tracepoint",
        .step = 1,
        .present = true,
    });
    ledger.observe(.guest_frame_presented, .{
        .tier = .rosette_model,
        .observer = "substitution-layer",
        .step = 2,
        .present = true,
    });
    ledger.observe(.guest_frame_presented, .{
        .tier = .instruction_pointer,
        .observer = "tracepoint:RefreshGuestOutput",
        .step = 3,
        .present = false,
    });
    try std.testing.expectEqual(@as(u8, 1), ledger.establishedSubjects());
    try std.testing.expectEqual(@as(u8, 1), ledger.unsafeSubjects());
}
