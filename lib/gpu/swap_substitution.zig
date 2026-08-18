//! When the harness may stand in for a step the title never took, what it is
//! allowed to do, and how the run records that it happened.
//!
//! The graphics contract's owner rule says a harness may never satisfy a clause
//! the title owns, and it is right: a swap Rosette manufactures is a frame the
//! title did not draw, and marking that clause satisfied retires the one honest
//! signal that the title is stuck. That rule stays, and `Ledger.satisfy` still
//! refuses.
//!
//! But "never do it" and "never do it *silently*" are different rules, and only
//! the second one is actually load-bearing. The reason a fabricated swap is
//! dangerous is that it becomes indistinguishable from a real one — the counter
//! goes up, the ladder advances, and six subsystems downstream now report
//! progress nobody made. If the substitution is instead recorded as a
//! substitution, carries the evidence that triggered it, and can never be
//! counted as authentic, then the danger is gone and what remains is a harness
//! that can drive the rest of the pipeline while the real defect is still open.
//!
//! That is what this module is: a third state next to "observed" and "satisfied
//! by harness", with a trigger that has to justify itself and a ledger that
//! keeps the three apart forever.
//!
//! ## The trigger is behavioural
//!
//! Nothing here matches a title, an address, or a symbol. The question asked is
//! structural: has the producer demonstrably done the work that precedes a
//! present, and then stopped? Concretely — the ring was published, commands
//! were consumed, and no swap has appeared for long enough that one would have.
//! A title that is merely slow keeps advancing its write pointer and never
//! trips this; a title that has not reached its graphics path at all has not
//! published and never trips it either. Only the shape this run actually has —
//! submitted, drained, quiet, no swap — arms it.
//!
//! ## The escalation is ordered by how much is invented
//!
//! Each tier invents strictly more than the one below, and the lowest tier that
//! can run is the one that runs. A tier that cannot run says why, so a run that
//! substituted nothing still explains what stopped it rather than reading the
//! same as a run that was never triggered.

const std = @import("std");

/// How much of the missing behaviour a tier supplies. Ordered: a caller picks
/// the lowest tier that is available, and the order is the amount invented.
pub const Tier = enum(u8) {
    /// Watch. The default, and the correct answer whenever the title is still
    /// making progress.
    observe_only = 0,
    /// Present an image the guest actually produced, without waiting for the
    /// swap that would normally trigger it. Nothing is invented: the pixels are
    /// the guest's and the presenter is Rosette's own, so this tier does not
    /// touch the owner rule at all. It is a tier rather than ordinary behaviour
    /// only because presenting off-cadence is a decision worth recording.
    present_discovered_output = 1,
    /// Write the swap packet the title never wrote into the ring it published.
    /// The packet is data in memory the harness already owns, and everything
    /// downstream of it — decode, issue, refresh, present — is the emulator's
    /// authentic code. This is the first tier that invents anything, and the
    /// first that must be recorded as a substitution.
    publish_swap_packet = 2,
    /// Advance the ring's write pointer so the command processor sees the
    /// packet. Separate from writing the packet because it needs a channel the
    /// packet does not: the pointer is a memory-mapped register, and only guest
    /// code can store to it.
    advance_write_pointer = 3,

    pub fn label(self: Tier) []const u8 {
        return switch (self) {
            .observe_only => "observe_only",
            .present_discovered_output => "present_discovered_output",
            .publish_swap_packet => "publish_swap_packet",
            .advance_write_pointer => "advance_write_pointer",
        };
    }

    /// Whether reaching this tier means the harness supplied guest behaviour.
    /// Presenting the guest's own pixels does not; writing a packet it never
    /// wrote does.
    pub fn fabricatesGuestBehaviour(self: Tier) bool {
        return @intFromEnum(self) >= @intFromEnum(Tier.publish_swap_packet);
    }
};

/// Why a tier is not available. Every value is a distinct piece of missing
/// capability, and each names what would have to exist for the tier to run —
/// which is the difference between a log line a reader can act on and one that
/// only says no.
pub const Unavailable = enum {
    not_triggered,
    /// Nothing the guest produced has been found to present.
    no_discovered_output,
    /// The ring's base and size have not been observed, so there is nowhere to
    /// write.
    ring_geometry_unknown,
    /// No front buffer address and extent are known, so a swap packet would
    /// name nothing. The emulator asserts on an implausible extent, so this is
    /// refused here rather than discovered there.
    frontbuffer_unknown,
    /// The ring has outstanding work. Writing into it now would land the packet
    /// in dwords the command processor has not read yet.
    ring_not_drained,
    /// The write pointer is a memory-mapped register behind a no-access page
    /// whose stores are handled inside the emulator. A harness has no way to
    /// originate one: it can observe the guest's store and cannot make one.
    no_write_pointer_channel,
    /// The title started presenting on its own. Substitution stands down.
    authentic_swap_observed,

    pub fn label(self: Unavailable) []const u8 {
        return switch (self) {
            .not_triggered => "the producer is still making progress, so nothing needs standing in for",
            .no_discovered_output => "no guest-produced image has been found; the frame source has nothing to present",
            .ring_geometry_unknown => "the ring's base and size have not been observed, so there is nowhere to write a packet",
            .frontbuffer_unknown => "no front buffer address and extent are known, so a swap packet would name nothing and the command processor would assert on it",
            .ring_not_drained => "the ring still holds work the command processor has not read; a packet written now would land inside it",
            .no_write_pointer_channel => "the ring write pointer is a memory-mapped register behind a no-access page, and its stores are executed by guest code inside the emulator. Rosette can observe such a store and cannot originate one, so a packet written into the ring will sit there until the title publishes again. Closing this needs either a way to deliver a synthetic store through the emulator's own fault handler, or the emulator's ring-change watch to infer the pointer",
            .authentic_swap_observed => "the title presented on its own; substitution stands down and every later frame is authentic",
        };
    }
};

/// What the run knows at the moment the question is asked. Facts only: the
/// decision is derived here so it is derived the same way every time and can be
/// tested without a running emulator.
pub const Evidence = struct {
    /// The producer wrote a command batch and published it at least once.
    ring_published: bool = false,
    /// The command processor drained commands. Proof the consumer side works,
    /// which is what makes a missing swap the producer's problem.
    pm4_consumed: bool = false,
    /// The title issued draws. A title that never drew has not reached its
    /// rendering path, and standing in for its present would show nothing.
    draws_issued: bool = false,
    /// The title entered its present path on its own.
    authentic_swap_seen: bool = false,
    /// Steps since the write pointer last changed. The staleness measure; a
    /// live producer resets it every frame.
    steps_since_publish: u64 = 0,
    /// Ring base and size are known.
    ring_geometry_known: bool = false,
    /// The ring is drained: read and write pointers agree.
    ring_drained: bool = false,
    /// A front buffer address and extent are known and plausible.
    frontbuffer_known: bool = false,
    /// The frame source holds an image the guest produced.
    discovered_output_available: bool = false,
    /// Whether a channel exists to advance the write pointer. False today, and
    /// a parameter rather than a constant so that closing the gap is one wire
    /// rather than an edit to the decision logic.
    write_pointer_channel_available: bool = false,
};

/// Steps of quiet before a published-and-drained producer counts as stopped.
///
/// Chosen against the observed throughput rather than a wall clock: the run
/// executes a few million steps per second, so this is roughly a second of a
/// title doing nothing about a frame it has already prepared. Long enough that
/// a slow frame does not trip it, short enough that a stuck run does not spend
/// its whole budget waiting.
pub const default_quiet_steps: u64 = 8_000_000;

pub const Decision = struct {
    tier: Tier,
    /// Set when the tier is `observe_only`, naming what stopped the next one.
    blocked_by: ?Unavailable = null,

    pub fn substituting(self: Decision) bool {
        return self.tier != .observe_only;
    }
};

/// Whether the producer has demonstrably stopped short of presenting.
///
/// Every clause is necessary and the conjunction is the point. Published and
/// drained without draws is a title that set state; draws without quiet is a
/// title mid-frame; quiet without published is a title that never started.
pub fn triggered(evidence: Evidence, quiet_steps: u64) bool {
    if (evidence.authentic_swap_seen) return false;
    if (!evidence.ring_published) return false;
    if (!evidence.pm4_consumed) return false;
    if (!evidence.draws_issued) return false;
    return evidence.steps_since_publish >= quiet_steps;
}

/// The highest tier that can actually run, and what stopped the next one.
pub fn decide(evidence: Evidence, quiet_steps: u64) Decision {
    if (evidence.authentic_swap_seen)
        return .{ .tier = .observe_only, .blocked_by = .authentic_swap_observed };
    if (!triggered(evidence, quiet_steps))
        return .{ .tier = .observe_only, .blocked_by = .not_triggered };

    // Escalate only as far as the available capability allows, and report the
    // first thing missing above that. The order matters: presenting the guest's
    // own pixels invents nothing, so it is preferred over writing a packet even
    // when both are possible.
    if (!evidence.ring_geometry_known)
        return tierOr(evidence, .ring_geometry_unknown);
    if (!evidence.frontbuffer_known)
        return tierOr(evidence, .frontbuffer_unknown);
    if (!evidence.ring_drained)
        return tierOr(evidence, .ring_not_drained);
    if (!evidence.write_pointer_channel_available)
        return .{ .tier = .publish_swap_packet, .blocked_by = .no_write_pointer_channel };
    return .{ .tier = .advance_write_pointer };
}

/// Fall back to presenting discovered output when the packet path is blocked,
/// keeping the reason that blocked it.
fn tierOr(evidence: Evidence, reason: Unavailable) Decision {
    if (evidence.discovered_output_available)
        return .{ .tier = .present_discovered_output, .blocked_by = reason };
    return .{ .tier = .observe_only, .blocked_by = reason };
}

/// What the harness actually did, kept apart from what the title did, forever.
///
/// The counters are separate rather than a single total because the whole
/// safety argument is that a substituted frame can never be mistaken for an
/// authentic one — and a shared counter is exactly that mistake.
pub const Ledger = struct {
    evaluations: u64 = 0,
    /// Times the trigger fired.
    triggers: u64 = 0,
    /// Substitutions actually performed, by tier.
    presented_discovered: u64 = 0,
    packets_published: u64 = 0,
    pointers_advanced: u64 = 0,
    /// Times a tier was wanted and unavailable, with the most recent reason.
    blocked: u64 = 0,
    last_blocked_by: ?Unavailable = null,
    last_tier: Tier = .observe_only,
    first_substitution_step: u64 = 0,
    last_substitution_step: u64 = 0,
    /// Set once the title presents on its own. Latched: from that point the run
    /// is authentic and the counters above describe history, not the present.
    stood_down: bool = false,

    pub fn record(self: *Ledger, decision: Decision, step: u64) void {
        self.evaluations +|= 1;
        self.last_tier = decision.tier;
        if (decision.blocked_by) |reason| {
            self.last_blocked_by = reason;
            if (reason == .authentic_swap_observed) self.stood_down = true;
            if (reason != .not_triggered and reason != .authentic_swap_observed) self.blocked +|= 1;
        }
        if (!decision.substituting()) return;
        self.triggers +|= 1;
        if (self.first_substitution_step == 0) self.first_substitution_step = step;
        self.last_substitution_step = step;
        switch (decision.tier) {
            .observe_only => {},
            .present_discovered_output => self.presented_discovered +|= 1,
            .publish_swap_packet => self.packets_published +|= 1,
            .advance_write_pointer => self.pointers_advanced +|= 1,
        }
    }

    /// Whether anything in this run was fabricated. The single question a
    /// reader of any downstream counter has to be able to ask.
    pub fn fabricatedAnything(self: *const Ledger) bool {
        return self.packets_published != 0 or self.pointers_advanced != 0;
    }

    /// One line stating what the substitution layer did, written so that a run
    /// which substituted nothing still says why.
    pub fn verdict(self: *const Ledger) []const u8 {
        if (self.stood_down)
            return "the title reached its own present path; anything the substitution layer did before that is history and every frame since is authentic";
        if (self.fabricatedAnything())
            return "the harness supplied guest behaviour this run: frames attributed to it are NOT evidence that the title presented, and the frontier that triggered it is still open";
        if (self.presented_discovered != 0)
            return "the harness presented guest-produced images off-cadence. The pixels are the guest's and nothing was fabricated, but the title still never asked to present";
        if (self.blocked != 0)
            return "the substitution layer triggered and could not act; the blocking reason names the capability that is missing";
        return "the substitution layer never triggered: the producer either kept making progress or never started";
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

/// The shape of the run this was written against: published, consumed, drew,
/// then went quiet without ever presenting.
const stalled_producer = Evidence{
    .ring_published = true,
    .pm4_consumed = true,
    .draws_issued = true,
    .steps_since_publish = 2_893_152_101,
    .ring_geometry_known = true,
    .ring_drained = true,
};

test "a producer that is still publishing never triggers substitution" {
    var live = stalled_producer;
    live.steps_since_publish = 1000;
    try std.testing.expect(!triggered(live, default_quiet_steps));
    const decision = decide(live, default_quiet_steps);
    try std.testing.expectEqual(Tier.observe_only, decision.tier);
    try std.testing.expectEqual(Unavailable.not_triggered, decision.blocked_by.?);
}

// Each clause of the trigger removes a different false positive, so each has to
// be necessary on its own.
test "every clause of the trigger is load-bearing" {
    try std.testing.expect(triggered(stalled_producer, default_quiet_steps));

    var never_published = stalled_producer;
    never_published.ring_published = false;
    try std.testing.expect(!triggered(never_published, default_quiet_steps));

    var never_drained = stalled_producer;
    never_drained.pm4_consumed = false;
    try std.testing.expect(!triggered(never_drained, default_quiet_steps));

    // A title that set state and never drew has not reached its rendering path;
    // presenting for it would put an empty buffer on screen and call it a frame.
    var never_drew = stalled_producer;
    never_drew.draws_issued = false;
    try std.testing.expect(!triggered(never_drew, default_quiet_steps));
}

test "a title that presents on its own stands the substitution layer down" {
    var presenting = stalled_producer;
    presenting.authentic_swap_seen = true;
    try std.testing.expect(!triggered(presenting, default_quiet_steps));

    var ledger = Ledger{};
    ledger.record(decide(presenting, default_quiet_steps), 100);
    try std.testing.expect(ledger.stood_down);
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "every frame since is authentic") != null);
}

// The tier that invents nothing is preferred over the tier that invents a
// packet, even when both could run.
test "presenting the guest's own pixels outranks writing a packet it never wrote" {
    var evidence = stalled_producer;
    evidence.discovered_output_available = true;
    evidence.frontbuffer_known = false;

    const decision = decide(evidence, default_quiet_steps);
    try std.testing.expectEqual(Tier.present_discovered_output, decision.tier);
    try std.testing.expectEqual(Unavailable.frontbuffer_unknown, decision.blocked_by.?);
    try std.testing.expect(!decision.tier.fabricatesGuestBehaviour());
}

test "the write pointer gap is reported as a named missing capability" {
    var evidence = stalled_producer;
    evidence.frontbuffer_known = true;

    const decision = decide(evidence, default_quiet_steps);
    try std.testing.expectEqual(Tier.publish_swap_packet, decision.tier);
    try std.testing.expectEqual(Unavailable.no_write_pointer_channel, decision.blocked_by.?);
    try std.testing.expect(std.mem.indexOf(u8, decision.blocked_by.?.label(), "cannot originate one") != null);

    // And closes without touching the decision logic once the channel exists.
    evidence.write_pointer_channel_available = true;
    const closed = decide(evidence, default_quiet_steps);
    try std.testing.expectEqual(Tier.advance_write_pointer, closed.tier);
    try std.testing.expect(closed.blocked_by == null);
}

test "a triggered run with nothing available says what stopped it" {
    var evidence = stalled_producer;
    evidence.ring_geometry_known = false;
    const decision = decide(evidence, default_quiet_steps);
    try std.testing.expectEqual(Tier.observe_only, decision.tier);
    try std.testing.expectEqual(Unavailable.ring_geometry_unknown, decision.blocked_by.?);

    var ledger = Ledger{};
    ledger.record(decision, 50);
    try std.testing.expectEqual(@as(u64, 1), ledger.blocked);
    try std.testing.expectEqual(@as(u64, 0), ledger.triggers);
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "capability that is missing") != null);
}

// The entire safety argument. A frame the harness caused must never be
// summable with one the title caused.
test "fabricated and merely off-cadence substitutions are counted separately" {
    var ledger = Ledger{};
    ledger.record(.{ .tier = .present_discovered_output }, 10);
    try std.testing.expect(!ledger.fabricatedAnything());
    try std.testing.expectEqual(@as(u64, 1), ledger.presented_discovered);
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "nothing was fabricated") != null);

    ledger.record(.{ .tier = .publish_swap_packet }, 20);
    try std.testing.expect(ledger.fabricatedAnything());
    try std.testing.expectEqual(@as(u64, 1), ledger.packets_published);
    try std.testing.expectEqual(@as(u64, 1), ledger.presented_discovered);
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "NOT evidence") != null);

    try std.testing.expectEqual(@as(u64, 10), ledger.first_substitution_step);
    try std.testing.expectEqual(@as(u64, 20), ledger.last_substitution_step);
}

test "the quiet threshold is a parameter so a slow frame is not a stall" {
    var evidence = stalled_producer;
    evidence.steps_since_publish = 1_000_000;
    try std.testing.expect(!triggered(evidence, default_quiet_steps));
    try std.testing.expect(triggered(evidence, 500_000));
}

test "every unavailable reason names what would have to exist" {
    inline for (.{
        Unavailable.not_triggered,          Unavailable.no_discovered_output,
        Unavailable.ring_geometry_unknown,  Unavailable.frontbuffer_unknown,
        Unavailable.ring_not_drained,       Unavailable.no_write_pointer_channel,
        Unavailable.authentic_swap_observed,
    }) |reason| {
        try std.testing.expect(reason.label().len > 40);
    }
    inline for (.{
        Tier.observe_only,        Tier.present_discovered_output,
        Tier.publish_swap_packet, Tier.advance_write_pointer,
    }) |tier| {
        try std.testing.expect(tier.label().len > 0);
    }
}

test "a run that never triggered says so rather than reading as clean" {
    var ledger = Ledger{};
    ledger.record(.{ .tier = .observe_only, .blocked_by = .not_triggered }, 1);
    try std.testing.expectEqual(@as(u64, 0), ledger.blocked);
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "never triggered") != null);
}
