//! Who moved the ring's write pointer, and whether the observers agree that
//! anyone did.
//!
//! Three independent things in this run claim to know whether the producer
//! published, and in the run this was written for they disagreed completely:
//!
//!   * Rosette's ring tracker: two writes, one advance, `published=YES`.
//!   * The emulator's own counter: `wptr_updates(total=0, guest=0,
//!     last_source=unknown)`.
//!   * The register aperture observer: `verdict=never_accessed` — not one
//!     access to the memory-mapped register the write pointer lives in.
//!
//! All three cannot be right, and the interesting part is *why* each believes
//! what it believes. Rosette's tracker is fed by parsing a line the emulator
//! printed; the emulator's counter is incremented where it actually applies a
//! pointer update; the aperture observer sees the faults a guest store to the
//! register would raise. So the disagreement is not noise — it localises the
//! event. A pointer the emulator printed and never applied means the print site
//! and the apply site are different code paths. A pointer nothing stored means
//! it never came from the title at all.
//!
//! ## Why this is a predictor and not a counter
//!
//! `published()` is a latch, and a latch fed by a log line is a claim about
//! text. Everything downstream — the ladder, the swap health blocker, the
//! substitution trigger — treats it as a claim about the guest. This module
//! keeps the sources apart, names the strongest evidence each one is, and
//! refuses to let the weakest promote itself to the strongest.

const std = @import("std");

/// How an observer came to believe the write pointer moved. Ordered by how
/// close the observation is to the hardware event; a stronger source is one
/// that is harder to be wrong about.
pub const Source = enum(u8) {
    /// Parsed out of a line the emulator printed. Proof the emulator's logging
    /// ran, not that a pointer was applied.
    emulator_log_line = 0,
    /// The emulator's own applied-update counter.
    emulator_counter = 1,
    /// A guest store that faulted into the memory-mapped register aperture.
    /// The strongest: the aperture's pages are unreadable by design, so a store
    /// to the register cannot happen without arriving here.
    guest_register_store = 2,
    /// Command dwords found in ring memory. Not the pointer itself, but the
    /// only direct evidence that a producer wrote anything at all.
    ring_memory_contents = 3,

    pub fn label(self: Source) []const u8 {
        return switch (self) {
            .emulator_log_line => "emulator_log_line",
            .emulator_counter => "emulator_counter",
            .guest_register_store => "guest_register_store",
            .ring_memory_contents => "ring_memory_contents",
        };
    }

    pub fn strength(self: Source) []const u8 {
        return switch (self) {
            .emulator_log_line => "weakest: proves the emulator's logging ran, not that a pointer was applied. A print site and an apply site can be different code paths",
            .emulator_counter => "moderate: the emulator incremented this where it applies an update, so it is a claim about the emulator's own state machine",
            .guest_register_store => "strongest for the pointer: the aperture's pages are unreadable by design, so a guest store to the register cannot happen without faulting into this observer",
            .ring_memory_contents => "strongest for the payload: dwords in the ring were written by something, whatever any pointer counter says",
        };
    }
};

pub const source_count = 4;

/// What one observer counted.
pub const Observation = struct {
    source: Source,
    /// Whether this observer was in a position to see anything at all. An
    /// observer that was never wired up reporting zero is not evidence of
    /// absence, and conflating the two is how a missing hook reads as a
    /// missing guest.
    active: bool = false,
    events: u64 = 0,

    pub fn claimsMovement(self: Observation) bool {
        return self.active and self.events != 0;
    }
};

/// What the disagreement between the observers means. Each value names a
/// different place to look, which is the only reason to have five of them.
pub const Finding = enum {
    /// Nothing has been observed by anyone yet.
    nothing_observed,
    /// Every active observer agrees the producer published.
    agreed_published,
    /// Every active observer agrees nothing was published.
    agreed_silent,
    /// The emulator printed a pointer update that neither its own counter nor
    /// the aperture saw. The print site and the apply site have diverged.
    printed_but_not_applied,
    /// Command dwords are in the ring and no observer saw a pointer move. The
    /// payload exists and was never published.
    payload_without_publication,
    /// A pointer moved and the ring holds nothing. The producer published an
    /// empty span.
    publication_without_payload,

    pub fn label(self: Finding) []const u8 {
        return switch (self) {
            .nothing_observed => "nothing_observed",
            .agreed_published => "agreed_published",
            .agreed_silent => "agreed_silent",
            .printed_but_not_applied => "PRINTED_BUT_NOT_APPLIED",
            .payload_without_publication => "PAYLOAD_WITHOUT_PUBLICATION",
            .publication_without_payload => "PUBLICATION_WITHOUT_PAYLOAD",
        };
    }

    pub fn meaning(self: Finding) []const u8 {
        return switch (self) {
            .nothing_observed => "no observer has seen anything yet, so nothing can be concluded about the producer",
            .agreed_published => "every active observer agrees the producer published a span, so treating the ring as live is safe",
            .agreed_silent => "every active observer agrees nothing has been submitted. The producer has not run, and no counter downstream of it means anything yet",
            .printed_but_not_applied => "the emulator printed a write-pointer update that neither its own applied-update counter nor the register aperture observed. Its logging ran and its state machine did not, so the two are different code paths — and every downstream latch fed by that log line is asserting something the emulator does not itself believe. Trust the counter and the aperture over the line",
            .payload_without_publication => "command dwords are in ring memory and no observer saw the write pointer move. The producer built a batch and never published it, which is a control-flow problem in the submitting thread rather than anything downstream of the ring",
            .publication_without_payload => "the write pointer moved and the ring holds no command dwords. The producer published an empty span: its submission path ran with nothing behind it, which is the opposite of a consumer that failed to drain",
        };
    }

    /// Whether this finding means a downstream reader should not trust
    /// `published()`.
    pub fn undermines_publication(self: Finding) bool {
        return self == .printed_but_not_applied or self == .publication_without_payload;
    }
};

pub const Ledger = struct {
    observations: [source_count]Observation = .{
        .{ .source = .emulator_log_line },
        .{ .source = .emulator_counter },
        .{ .source = .guest_register_store },
        .{ .source = .ring_memory_contents },
    },

    pub fn record(self: *Ledger, source: Source, active: bool, events: u64) void {
        const entry = &self.observations[@intFromEnum(source)];
        entry.active = active;
        entry.events = events;
    }

    pub fn get(self: *const Ledger, source: Source) Observation {
        return self.observations[@intFromEnum(source)];
    }

    pub fn activeCount(self: *const Ledger) u32 {
        var count: u32 = 0;
        for (self.observations) |entry| {
            if (entry.active) count += 1;
        }
        return count;
    }

    /// The strongest active observer that claims the pointer moved. Named so a
    /// report can say what its belief actually rests on.
    pub fn strongestPointerEvidence(self: *const Ledger) ?Source {
        var chosen: ?Source = null;
        for (self.observations) |entry| {
            if (entry.source == .ring_memory_contents) continue;
            if (!entry.claimsMovement()) continue;
            if (chosen == null or @intFromEnum(entry.source) > @intFromEnum(chosen.?)) chosen = entry.source;
        }
        return chosen;
    }

    pub fn finding(self: *const Ledger) Finding {
        if (self.activeCount() == 0) return .nothing_observed;

        const payload = self.get(.ring_memory_contents);
        const line = self.get(.emulator_log_line);
        const counter = self.get(.emulator_counter);
        const aperture = self.get(.guest_register_store);

        const pointer_moved = line.claimsMovement() or counter.claimsMovement() or aperture.claimsMovement();
        const corroborated = counter.claimsMovement() or aperture.claimsMovement();

        // The specific disagreement this module was written for, and it has to
        // be checked before the agreement cases: a log line asserting movement
        // that no applier saw is not "published", it is a divergence.
        if (line.claimsMovement() and !corroborated and
            (counter.active or aperture.active)) return .printed_but_not_applied;

        if (payload.claimsMovement() and !pointer_moved) return .payload_without_publication;
        if (pointer_moved and payload.active and !payload.claimsMovement()) return .publication_without_payload;
        if (pointer_moved) return .agreed_published;
        return .agreed_silent;
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

/// Exactly what the observed run reported: a printed pointer update, an
/// emulator counter at zero, an aperture that was never touched, and a ring
/// holding seventeen non-zero dwords.
fn observedRun() Ledger {
    var ledger = Ledger{};
    ledger.record(.emulator_log_line, true, 2);
    ledger.record(.emulator_counter, true, 0);
    ledger.record(.guest_register_store, true, 0);
    ledger.record(.ring_memory_contents, true, 17);
    return ledger;
}

test "a printed pointer nobody applied is a divergence rather than a publication" {
    const ledger = observedRun();
    try std.testing.expectEqual(Finding.printed_but_not_applied, ledger.finding());
    try std.testing.expect(ledger.finding().undermines_publication());
    try std.testing.expect(std.mem.indexOf(u8, ledger.finding().meaning(), "different code paths") != null);
    // The strongest thing believing the pointer moved is the weakest source.
    try std.testing.expectEqual(Source.emulator_log_line, ledger.strongestPointerEvidence().?);
}

// An observer that was never wired up reporting zero is not evidence of
// absence, and conflating the two makes a missing hook read as a missing guest.
test "an inactive observer is not evidence of absence" {
    var ledger = Ledger{};
    ledger.record(.emulator_log_line, true, 2);
    ledger.record(.emulator_counter, false, 0);
    ledger.record(.guest_register_store, false, 0);
    ledger.record(.ring_memory_contents, true, 17);
    // Nothing contradicts the line, so this is agreement rather than divergence.
    try std.testing.expectEqual(Finding.agreed_published, ledger.finding());
    try std.testing.expectEqual(@as(u32, 2), ledger.activeCount());
}

test "corroboration by the aperture makes a printed pointer trustworthy" {
    var ledger = observedRun();
    ledger.record(.guest_register_store, true, 2);
    try std.testing.expectEqual(Finding.agreed_published, ledger.finding());
    try std.testing.expect(!ledger.finding().undermines_publication());
    try std.testing.expectEqual(Source.guest_register_store, ledger.strongestPointerEvidence().?);
}

test "a batch that was built and never published names the submitting thread" {
    var ledger = Ledger{};
    ledger.record(.emulator_log_line, true, 0);
    ledger.record(.emulator_counter, true, 0);
    ledger.record(.guest_register_store, true, 0);
    ledger.record(.ring_memory_contents, true, 25);
    try std.testing.expectEqual(Finding.payload_without_publication, ledger.finding());
    try std.testing.expect(std.mem.indexOf(u8, ledger.finding().meaning(), "submitting thread") != null);
}

test "a pointer that moved over an empty ring is an empty submission" {
    var ledger = Ledger{};
    ledger.record(.emulator_log_line, true, 2);
    ledger.record(.emulator_counter, true, 2);
    ledger.record(.guest_register_store, true, 2);
    ledger.record(.ring_memory_contents, true, 0);
    try std.testing.expectEqual(Finding.publication_without_payload, ledger.finding());
    try std.testing.expect(ledger.finding().undermines_publication());
}

test "silence from every active observer is agreement, not absence of evidence" {
    var ledger = Ledger{};
    ledger.record(.emulator_log_line, true, 0);
    ledger.record(.emulator_counter, true, 0);
    ledger.record(.guest_register_store, true, 0);
    ledger.record(.ring_memory_contents, true, 0);
    try std.testing.expectEqual(Finding.agreed_silent, ledger.finding());
    try std.testing.expect(ledger.strongestPointerEvidence() == null);
    try std.testing.expect(std.mem.indexOf(u8, ledger.finding().meaning(), "has not run") != null);
}

test "an empty ledger concludes nothing" {
    const ledger = Ledger{};
    try std.testing.expectEqual(Finding.nothing_observed, ledger.finding());
    try std.testing.expectEqual(@as(u32, 0), ledger.activeCount());
}

// Ring contents prove a payload, never a pointer. Letting them stand in for
// pointer evidence would make a built-but-unpublished batch read as published.
test "ring contents never count as evidence that the pointer moved" {
    var ledger = Ledger{};
    ledger.record(.ring_memory_contents, true, 100);
    try std.testing.expect(ledger.strongestPointerEvidence() == null);
    try std.testing.expectEqual(Finding.payload_without_publication, ledger.finding());
}

test "every source and finding explains itself" {
    inline for (.{
        Source.emulator_log_line,     Source.emulator_counter,
        Source.guest_register_store,  Source.ring_memory_contents,
    }) |source| {
        try std.testing.expect(source.label().len > 0);
        try std.testing.expect(source.strength().len > 40);
    }
    inline for (.{
        Finding.nothing_observed,             Finding.agreed_published,
        Finding.agreed_silent,                Finding.printed_but_not_applied,
        Finding.payload_without_publication,  Finding.publication_without_payload,
    }) |finding| {
        try std.testing.expect(finding.label().len > 0);
        try std.testing.expect(finding.meaning().len > 40);
    }
}
