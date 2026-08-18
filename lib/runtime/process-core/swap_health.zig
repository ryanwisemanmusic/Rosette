//! SWAP HEALTH — why a frame boundary is not being reached, said in one line.
//!
//! The graphics frontier already reports that `VdSwap` was never entered, and
//! that is true and insufficient. "Never entered" is the same sentence for a
//! producer that never started, a producer that ran once and stopped, and a
//! producer that is running right now into a consumer that is not draining.
//! Those need opposite investigations, and the difference between them is not
//! visible in any single subsystem's counters — it is in the *join*.
//!
//! This module does the join and nothing else. It reads state three other
//! subsystems already maintain, and returns the one blocker that explains the
//! rest:
//!
//!   * ring publication — did the write pointer ever move, and how long ago
//!   * the guest log cycle detector — is the guest repeating itself forever
//!   * the bootstrap contract — which precondition has not been met
//!
//! The distinction that mattered in the run this was written for: the ring
//! *was* published (`ring_published=YES`, twenty-two dwords consumed), which
//! made every downstream report look like a consumer problem. The write pointer
//! had not moved in ten billion steps and the guest was rotating through two
//! log lines. The producer had stopped, and no amount of looking at the command
//! processor or the presenter was going to show that.
//!
//! Deliberately no forcing and no synthesis. A swap Rosette manufactures is a
//! frame the title did not draw, and it would retire the one signal that says
//! the title is stuck. This reports; it does not intervene.
//!
//! Cost: called from the graphics frontier checkpoint, which is already
//! throttled to a state change or one in sixty-four emissions.

const std = @import("std");

/// Producer liveness, from the ring write pointer alone.
pub const Producer = enum {
    /// The write pointer was never written. The producer has not reached its
    /// submission path.
    never_started,
    /// Written, never changed. The producer ran and had nothing to submit.
    started_never_published,
    /// Published, and the pointer has moved recently.
    live,
    /// Published, then went quiet for longer than the staleness bound.
    latched_then_stalled,
};

/// What is actually preventing a frame boundary.
pub const Blocker = enum {
    /// No swap is expected yet: the producer has not reached submission.
    producer_never_started,
    /// The producer submitted nothing, so there is no payload to swap.
    producer_published_nothing,
    /// The producer published and then stopped while the guest repeats itself.
    producer_stalled_in_guest_livelock,
    /// The producer published and then stopped, with no livelock evidence.
    producer_stalled_after_publication,
    /// The producer is live and a swap still has not been decoded — the
    /// frontier really is downstream of publication.
    consumer_not_reaching_swap,
    /// A swap was observed. Nothing to explain.
    healthy,

    pub fn label(self: Blocker) []const u8 {
        return switch (self) {
            .producer_never_started => "producer_never_started",
            .producer_published_nothing => "producer_published_nothing",
            .producer_stalled_in_guest_livelock => "producer_stalled_in_guest_livelock",
            .producer_stalled_after_publication => "producer_stalled_after_publication",
            .consumer_not_reaching_swap => "consumer_not_reaching_swap",
            .healthy => "healthy",
        };
    }

    /// The one sentence naming what to look at next. Phrased as "look here,
    /// not there", because every one of these has a plausible wrong subsystem
    /// that the raw counters point at.
    pub fn guidance(self: Blocker) []const u8 {
        return switch (self) {
            .producer_never_started =>
                "the guest never wrote the ring write pointer, so no frame was ever submitted. Look at what the title is doing instead of reaching its submission path — not at the command processor, the ring geometry or the presenter, none of which have been asked to do anything yet",
            .producer_published_nothing =>
                "the guest wrote the ring write pointer without ever changing it. The ring is configured and empty, so this is a producer with no payload rather than a consumer that failed to drain one",
            .producer_stalled_in_guest_livelock =>
                "the guest published, then stopped advancing the write pointer while repeating the same log lines. The producer is alive and making no progress: this is a livelock in guest code, and the swap will never arrive until that loop is broken. Ring publication being latched YES is what makes this look like a consumer problem — it is not",
            .producer_stalled_after_publication =>
                "the guest published once and has not advanced the write pointer since. `ring_published=YES` is a latch and does not mean the producer is still running — find what the submitting thread is waiting on",
            .consumer_not_reaching_swap =>
                "the producer is advancing the write pointer and no swap packet has been decoded. This one really is downstream: look at packet decode and the command processor, in that order",
            .healthy => "a swap was observed; the frame boundary is being reached",
        };
    }
};

pub const Assessment = struct {
    producer: Producer,
    blocker: Blocker,
    /// Steps since the write pointer last moved, or null when it never did.
    stalled_steps: ?u64 = null,
    advances: u64 = 0,
    writes: u64 = 0,
    published: bool = false,
    guest_livelocked: bool = false,
    swap_seen: bool = false,
};

/// Steps of write-pointer silence after which a published producer is treated
/// as stalled rather than merely between frames.
///
/// A title submitting at sixty frames per second advances the pointer far more
/// often than this; the run that motivated the module was silent for ten
/// billion. The bound only has to separate those two, and being generous costs
/// nothing but a later first report.
pub const STALL_STEPS: u64 = 500_000_000;

/// The whole decision, as a pure function of the inputs it is given.
///
/// Kept free of any state type so the reasoning can be tested directly: this is
/// the sentence a reader will act on, and it is the part that can be wrong in a
/// way no compiler catches.
pub fn assess(
    writes: u64,
    advances: u64,
    published: bool,
    stalled_steps: ?u64,
    guest_livelocked: bool,
    swap_seen: bool,
) Assessment {
    const producer: Producer = blk: {
        if (writes == 0) break :blk .never_started;
        if (!published) break :blk .started_never_published;
        const age = stalled_steps orelse break :blk .live;
        break :blk if (age >= STALL_STEPS) .latched_then_stalled else .live;
    };
    const blocker: Blocker = blk: {
        if (swap_seen) break :blk .healthy;
        break :blk switch (producer) {
            .never_started => .producer_never_started,
            .started_never_published => .producer_published_nothing,
            .live => .consumer_not_reaching_swap,
            // A livelocked guest is a strictly more specific finding than a
            // quiet one, and naming the loop is what makes the report
            // actionable rather than merely accurate.
            .latched_then_stalled => if (guest_livelocked)
                .producer_stalled_in_guest_livelock
            else
                .producer_stalled_after_publication,
        };
    };
    return .{
        .producer = producer,
        .blocker = blocker,
        .stalled_steps = stalled_steps,
        .advances = advances,
        .writes = writes,
        .published = published,
        .guest_livelocked = guest_livelocked,
        .swap_seen = swap_seen,
    };
}

test "a producer that never wrote the pointer is not a consumer problem" {
    const result = assess(0, 0, false, null, false, false);
    try std.testing.expectEqual(Producer.never_started, result.producer);
    try std.testing.expectEqual(Blocker.producer_never_started, result.blocker);
}

test "writes without advances are an empty ring, not a failed drain" {
    const result = assess(4, 0, false, null, false, false);
    try std.testing.expectEqual(Producer.started_never_published, result.producer);
    try std.testing.expectEqual(Blocker.producer_published_nothing, result.blocker);
}

// The run this module exists for: two write-pointer writes at ~4.4 seconds,
// twenty-two dwords consumed, then ten billion steps of silence while the guest
// rotated through two log lines. Every downstream counter said the ring was
// published, which is true and points at the wrong half of the pipeline.
test "a latched publication plus a guest livelock names the producer, not the consumer" {
    const result = assess(2, 2, true, 10_300_000_000, true, false);
    try std.testing.expectEqual(Producer.latched_then_stalled, result.producer);
    try std.testing.expectEqual(Blocker.producer_stalled_in_guest_livelock, result.blocker);
    try std.testing.expect(std.mem.indexOf(u8, result.blocker.guidance(), "livelock") != null);

    // Without the livelock evidence the finding is weaker but still points at
    // the producer, because a latch is not liveness.
    const quiet = assess(2, 2, true, 10_300_000_000, false, false);
    try std.testing.expectEqual(Blocker.producer_stalled_after_publication, quiet.blocker);
}

test "a live producer with no swap is the one case that really is downstream" {
    const result = assess(9000, 8999, true, 1_000, false, false);
    try std.testing.expectEqual(Producer.live, result.producer);
    try std.testing.expectEqual(Blocker.consumer_not_reaching_swap, result.blocker);

    // Just under the bound is still live: a title between frames must not be
    // reported as a stalled one.
    const between_frames = assess(9000, 8999, true, STALL_STEPS - 1, true, false);
    try std.testing.expectEqual(Producer.live, between_frames.producer);
    try std.testing.expectEqual(Blocker.consumer_not_reaching_swap, between_frames.blocker);
}

test "an observed swap ends the analysis whatever the producer looks like" {
    // Health is decided by the frame boundary being reached, not by the
    // prettiness of the counters underneath it.
    const result = assess(2, 2, true, 10_300_000_000, true, true);
    try std.testing.expectEqual(Blocker.healthy, result.blocker);
    try std.testing.expectEqual(Producer.latched_then_stalled, result.producer);
}
