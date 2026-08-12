//! The guest-driven GPU bootstrap, as a contract with preconditions.
//!
//! A graphics stack that never produces a frame reports a wall of zeros:
//! callback = 0, read pointer = 0, write pointer = 0, swaps = 0, refresh
//! attempts = 0. Every one of those is true, none of them is the cause, and
//! reading them in any order tells you the same thing — that nothing happened.
//!
//! What decides where to look is *which step of the bootstrap was the first one
//! not to happen*, and whether the steps before it left the state its
//! precondition needs. That is a different question from "is the callback set",
//! and no count of zeros answers it.
//!
//! So the bootstrap is written down: an ordered set of interactions the guest
//! must perform, each with what must already be true for it to be reachable and
//! what observation proves it occurred. The runtime then reports the **frontier**
//! — the earliest step not yet observed — plus whether its precondition holds.
//! Those two facts together separate the three situations that look identical
//! from the outside:
//!
//!   * precondition **unmet** — the stall is upstream; this step was never
//!     reachable and investigating it is investigating a symptom;
//!   * precondition **met**, step not taken — the guest could have called and
//!     did not, so the question is why the guest's own code did not run;
//!   * step taken, later step blocked — the bootstrap is progressing and the
//!     frontier has moved, which is the only one of the three that is progress.
//!
//! Deliberately not a GPU implementation, and deliberately not a *substitute*
//! for the guest: nothing here registers a callback or primes a ring on the
//! guest's behalf. Synthesising a step the guest never took would make the one
//! honest signal in the whole subsystem — that the guest did not get there —
//! into a lie, and the frontier would then report progress that does not exist.

const std = @import("std");

/// The steps a title performs to bring the command ring up. Ordered by
/// dependency, not by the order any particular title happens to call them:
/// several are independent and a title may interleave them.
pub const Step = enum(u8) {
    /// Engine init. Establishes the graphics context the rest depends on.
    initialize_engines,
    /// The guest obtains the system command buffer it will write packets into.
    system_command_buffer,
    /// The guest registers the interrupt callback the GPU signals on vblank and
    /// swap. Without it the guest is never told a frame completed, so it never
    /// submits the next one — which is why a missing callback stalls the *whole*
    /// pipeline rather than only interrupts.
    graphics_interrupt_callback,
    /// The registered callback has actually entered and returned. Registration
    /// alone proves only that an address was stored, not that Rosette can run
    /// the producer notification path to completion.
    graphics_interrupt_dispatch,
    /// The guest hands the GPU a ring buffer base and size.
    ring_buffer,
    /// Read-pointer write-back, so the guest can observe consumption.
    rptr_writeback,
    /// Authentic guest data exists in the ring. This is deliberately separate
    /// from publishing the write pointer: a prepared PM4 packet with WPTR == 0
    /// is the exact boundary between command production and submission.
    ring_payload_prepared,
    /// The guest advances the ring write pointer: the first actual command
    /// submission, and the first evidence the pipeline carries data.
    ring_write_pointer,
    /// The command processor consumed the first authentic PM4 packet.
    pm4_packet_consumed,
    /// A completed frame presentation.
    swap,

    pub fn label(self: Step) []const u8 {
        return switch (self) {
            .initialize_engines => "VdInitializeEngines",
            .system_command_buffer => "VdGetSystemCommandBuffer",
            .graphics_interrupt_callback => "VdSetGraphicsInterruptCallback",
            .graphics_interrupt_dispatch => "graphics interrupt callback dispatch",
            .ring_buffer => "VdInitializeRingBuffer",
            .rptr_writeback => "VdEnableRingBufferRPtrWriteBack",
            .ring_payload_prepared => "authentic ring payload prepared",
            .ring_write_pointer => "ring write-pointer advance",
            .pm4_packet_consumed => "first authentic PM4 packet consumed",
            .swap => "VdSwap",
        };
    }

    /// Some titles allocate their own command ring and never ask for Xenia's
    /// system command buffer. Read-pointer write-back is useful but likewise
    /// not a prerequisite for publishing the first packet. Keep both facts in
    /// the observation record without allowing either to become a false
    /// bootstrap frontier.
    pub fn required(self: Step) bool {
        return switch (self) {
            .system_command_buffer, .rptr_writeback => false,
            else => true,
        };
    }

    /// What must already be true for the guest to be able to reach this step.
    /// `null` means the step is reachable from the start.
    pub fn precondition(self: Step) ?Step {
        return switch (self) {
            .initialize_engines => null,
            .system_command_buffer => null,
            .graphics_interrupt_callback => null,
            .graphics_interrupt_dispatch => .graphics_interrupt_callback,
            .ring_buffer => .initialize_engines,
            .rptr_writeback => .ring_buffer,
            .ring_payload_prepared => .ring_buffer,
            .ring_write_pointer => .ring_payload_prepared,
            .pm4_packet_consumed => .ring_write_pointer,
            .swap => .pm4_packet_consumed,
        };
    }

    /// What the runtime should look at when this step is the frontier.
    pub fn guidance(self: Step) []const u8 {
        return switch (self) {
            .initialize_engines,
            .system_command_buffer,
            .graphics_interrupt_callback,
            => "this step has no precondition inside the GPU bootstrap, so the guest could have called it at any point and did not. The stall is therefore NOT in the graphics stack: it is that the guest code which would make the call never executed. Look at guest thread progress and at any dispatch the runtime skipped or recovered, not at the GPU",
            .graphics_interrupt_dispatch => "the callback address is registered but an interrupt has not completed through it; inspect callback scheduling, guest execution and return rather than replacing the callback",
            .ring_buffer => "engine initialization completed but the title has not handed Xenia a command ring; inspect the guest's post-initialization control flow rather than creating a host ring on its behalf",
            .rptr_writeback => "the ring exists but the guest has not asked for read-pointer write-back; it will not observe consumption and may wait forever for progress it cannot see",
            .ring_payload_prepared => "the ring is configured but contains no authentic command payload; inspect the guest producer thread and the callback path that wakes it",
            .ring_write_pointer => "authentic PM4 data is already prepared in ring memory, but the guest has not published it. Inspect the producer's post-write control flow and the CP_RB_WPTR MMIO boundary; do not infer or force the pointer",
            .pm4_packet_consumed => "the guest published work, but the command processor has not consumed its first packet; inspect the worker wake event, reader offsets and packet decoder",
            .swap => "commands have reached the command processor but no frame has been presented; this is the first step where the presenter is implicated",
        };
    }
};

pub const step_count: usize = @typeInfo(Step).@"enum".fields.len;
pub const required_step_count: usize = countRequiredSteps();

fn countRequiredSteps() usize {
    var count: usize = 0;
    for (@typeInfo(Step).@"enum".fields) |field| {
        const step: Step = @enumFromInt(field.value);
        if (step.required()) count += 1;
    }
    return count;
}

pub const Observation = struct {
    seen: bool = false,
    /// Times observed. A step performed repeatedly is a running pipeline; a
    /// step performed once may be initialisation that never repeated.
    count: u64 = 0,
    /// Executed-step count at first observation, so the order the guest
    /// actually used can be compared with the dependency order.
    first_step: u64 = 0,
};

pub const Frontier = struct {
    /// Earliest step not observed, or null when the bootstrap is complete.
    step: ?Step = null,
    /// Whether that step's precondition is satisfied.
    precondition_met: bool = true,
    /// The unmet precondition, when there is one.
    blocked_by: ?Step = null,
    reached: usize = 0,
    /// Optional observations are useful route evidence, but never block the
    /// required frontier or inflate its denominator.
    optional_observed: usize = 0,
};

pub const Contract = struct {
    observations: [step_count]Observation = [_]Observation{.{}} ** step_count,
    /// Steps observed out of dependency order. Not an error — several steps are
    /// independent — but a title that swaps before submitting is worth knowing
    /// about.
    out_of_order: u64 = 0,

    pub fn observe(self: *Contract, step: Step, executed_steps: u64) void {
        const entry = &self.observations[@intFromEnum(step)];
        if (!entry.seen) {
            entry.seen = true;
            entry.first_step = executed_steps;
            if (step.precondition()) |required| {
                if (!self.observations[@intFromEnum(required)].seen) self.out_of_order +|= 1;
            }
        }
        entry.count +|= 1;
    }

    /// Record evidence whose meaning proves earlier data-path transitions.
    ///
    /// A consumed *authentic* PM4 packet cannot exist unless payload bytes
    /// were present and the producer published them to the command processor.
    /// Closing those two steps is deduction from a downstream observation,
    /// not synthetic GPU progress. Ordinary write-pointer observations still
    /// use `observe` because advancing a pointer alone does not prove payload.
    pub fn observeEvidence(self: *Contract, step: Step, executed_steps: u64) void {
        if (step == .pm4_packet_consumed) {
            self.observe(.ring_payload_prepared, executed_steps);
            self.observe(.ring_write_pointer, executed_steps);
        }
        self.observe(step, executed_steps);
    }

    pub fn seen(self: *const Contract, step: Step) bool {
        return self.observations[@intFromEnum(step)].seen;
    }

    pub fn frontier(self: *const Contract) Frontier {
        var result = Frontier{};
        inline for (@typeInfo(Step).@"enum".fields) |field| {
            const step: Step = @enumFromInt(field.value);
            if (comptime !step.required()) {
                if (self.seen(step)) result.optional_observed += 1;
            } else {
                if (self.seen(step)) {
                    result.reached += 1;
                } else if (result.step == null) {
                    result.step = step;
                    if (step.precondition()) |required| {
                        if (!self.seen(required)) {
                            result.precondition_met = false;
                            result.blocked_by = required;
                        }
                    }
                }
            }
        }
        return result;
    }

    pub fn complete(self: *const Contract) bool {
        return self.frontier().step == null;
    }
};

test "an untouched contract points at the first step and calls it reachable" {
    const contract = Contract{};
    const frontier = contract.frontier();
    try std.testing.expectEqual(Step.initialize_engines, frontier.step.?);
    try std.testing.expect(frontier.precondition_met);
    try std.testing.expectEqual(@as(usize, 0), frontier.reached);
}

// The distinction the wall of zeros cannot make: a step nobody could have taken
// versus a step everybody could have taken and nobody did.
test "an unmet precondition names the step that is actually blocking" {
    var contract = Contract{};
    contract.observe(.initialize_engines, 100);
    contract.observe(.system_command_buffer, 200);
    contract.observe(.graphics_interrupt_callback, 300);
    contract.observe(.graphics_interrupt_dispatch, 400);
    // Ring buffer never initialised, so write-pointer advance is unreachable.
    const frontier = contract.frontier();
    try std.testing.expectEqual(Step.ring_buffer, frontier.step.?);
    try std.testing.expect(frontier.precondition_met);
    try std.testing.expectEqual(@as(usize, 3), frontier.reached);
    try std.testing.expectEqual(@as(usize, 1), frontier.optional_observed);
}

test "a reachable-but-untaken step is distinguished from a blocked one" {
    var contract = Contract{};
    contract.observe(.ring_buffer, 100);
    // Frontier is initialize_engines, which has no precondition: reachable.
    var frontier = contract.frontier();
    try std.testing.expectEqual(Step.initialize_engines, frontier.step.?);
    try std.testing.expect(frontier.precondition_met);
    try std.testing.expect(frontier.blocked_by == null);

    // Now everything up to the write pointer except the ring itself.
    var blocked = Contract{};
    blocked.observe(.initialize_engines, 1);
    blocked.observe(.system_command_buffer, 2);
    blocked.observe(.graphics_interrupt_callback, 3);
    blocked.observe(.graphics_interrupt_dispatch, 4);
    blocked.observe(.rptr_writeback, 5);
    frontier = blocked.frontier();
    try std.testing.expectEqual(Step.ring_buffer, frontier.step.?);
    try std.testing.expect(frontier.precondition_met);

    // With the ring present, a missing write pointer blocks the swap.
    blocked.observe(.ring_buffer, 6);
    frontier = blocked.frontier();
    try std.testing.expectEqual(Step.ring_payload_prepared, frontier.step.?);

    blocked.observe(.ring_payload_prepared, 7);
    frontier = blocked.frontier();
    try std.testing.expectEqual(Step.ring_write_pointer, frontier.step.?);
    try std.testing.expect(frontier.precondition_met);

    blocked.observe(.ring_write_pointer, 8);
    frontier = blocked.frontier();
    try std.testing.expectEqual(Step.pm4_packet_consumed, frontier.step.?);

    blocked.observe(.pm4_packet_consumed, 9);
    frontier = blocked.frontier();
    try std.testing.expectEqual(Step.swap, frontier.step.?);
}

test "title-owned command ring does not require a system command buffer" {
    var contract = Contract{};
    contract.observe(.initialize_engines, 1);
    contract.observe(.graphics_interrupt_callback, 2);
    contract.observe(.graphics_interrupt_dispatch, 3);
    contract.observe(.ring_buffer, 4);
    contract.observe(.rptr_writeback, 5);
    contract.observe(.ring_payload_prepared, 6);

    const frontier = contract.frontier();
    try std.testing.expectEqual(Step.ring_write_pointer, frontier.step.?);
    try std.testing.expect(frontier.precondition_met);
    try std.testing.expectEqual(@as(usize, 5), frontier.reached);
    try std.testing.expectEqual(@as(usize, 1), frontier.optional_observed);
    try std.testing.expect(!contract.seen(.system_command_buffer));
}

test "a swap before any submission is recorded as out of order" {
    var contract = Contract{};
    contract.observe(.swap, 10);
    try std.testing.expectEqual(@as(u64, 1), contract.out_of_order);
    // Observing it again does not re-count: the ordering fact is about the
    // first occurrence.
    contract.observe(.swap, 20);
    try std.testing.expectEqual(@as(u64, 1), contract.out_of_order);
    try std.testing.expectEqual(@as(u64, 2), contract.observations[@intFromEnum(Step.swap)].count);
    try std.testing.expectEqual(@as(u64, 10), contract.observations[@intFromEnum(Step.swap)].first_step);
}

test "authentic PM4 consumption proves payload and publication" {
    var contract = Contract{};
    contract.observe(.initialize_engines, 1);
    contract.observe(.graphics_interrupt_callback, 2);
    contract.observe(.graphics_interrupt_dispatch, 3);
    contract.observe(.ring_buffer, 4);
    contract.observeEvidence(.pm4_packet_consumed, 5);

    try std.testing.expect(contract.seen(.ring_payload_prepared));
    try std.testing.expect(contract.seen(.ring_write_pointer));
    try std.testing.expect(contract.seen(.pm4_packet_consumed));
    try std.testing.expectEqual(Step.swap, contract.frontier().step.?);
}

test "a complete bootstrap has no frontier" {
    var contract = Contract{};
    inline for (@typeInfo(Step).@"enum".fields) |field| {
        contract.observe(@enumFromInt(field.value), field.value);
    }
    try std.testing.expect(contract.complete());
    try std.testing.expect(contract.frontier().step == null);
    try std.testing.expectEqual(required_step_count, contract.frontier().reached);
}

// The observed run: nothing at all, and the guidance has to send the reader out
// of the GPU rather than deeper into it.
test "the first step's guidance points away from the graphics stack" {
    const guidance = Step.graphics_interrupt_callback.guidance();
    try std.testing.expect(std.mem.indexOf(u8, guidance, "NOT in the graphics stack") != null);
    // And the later steps do not, because there the presenter is implicated.
    try std.testing.expect(std.mem.indexOf(u8, Step.swap.guidance(), "presenter") != null);
}
