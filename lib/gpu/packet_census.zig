//! Which PM4 opcodes the title actually put in the ring, and — the question
//! that decides the current investigation — whether it ever asked to be told
//! its work had finished.
//!
//! ## Why the opcode list matters more than the counts
//!
//! Every report so far says how many packets were consumed and how many of them
//! were draws. Neither number answers what a stalled title is actually waiting
//! for, because the packets that matter for that are the ones nobody counts:
//! `PM4_INTERRUPT`, which raises the graphics interrupt with source 1 when the
//! command processor reaches it, and the `EVENT_WRITE` family, which writes a
//! value into guest memory that the title polls.
//!
//! On 2026-08-31 the title published one batch — twenty-five root dwords,
//! seventy-two packets, twenty-four draws — and then polled a manual-reset
//! event three hundred and six times that nothing ever signalled. Two
//! explanations fit that exactly, and they are opposite:
//!
//! * the batch contained a completion request and the emulator never delivered
//!   it — an emulator defect, and every `DispatchInterruptCallback` call site
//!   in the macOS fork passes `source=0`, so a source-1 delivery would have to
//!   come from the `PM4_INTERRUPT` handler alone;
//! * the batch contained no completion request at all — in which case the title
//!   is waiting for something that is not the GPU, and looking for a missing
//!   interrupt is looking for something nobody asked for.
//!
//! One opcode census separates them. Nothing in the run could.
//!
//! ## Delivery is counted apart from the request
//!
//! `requested` comes from the ring; `delivered` comes from the interrupt
//! dispatch actually reaching the guest with the matching source. Keeping them
//! apart is the whole point: a request with no delivery names the emulator, and
//! a delivery with no request means something other than the title caused it.

const std = @import("std");
const pm4 = @import("xenia_pm4_contract");

pub const Type3Opcode = pm4.Type3Opcode;

/// Distinct opcodes retained. The console's type-3 space is 128 wide and a
/// title uses a small corner of it; this holds every opcode a real batch has
/// been observed to contain with room to spare.
pub const capacity: usize = 48;

pub const Entry = struct {
    opcode: u8 = 0,
    count: u64 = 0,
    first_step: u64 = 0,
    last_step: u64 = 0,

    pub fn typed(self: Entry) Type3Opcode {
        return @enumFromInt(self.opcode);
    }

    /// The opcode's name, or `<unnamed>` for one the contract's table does not
    /// cover. Not an error: the console's type-3 space is wider than the
    /// emulator's table, and an unnamed opcode in a report is more honest than
    /// a number formatted as if it had been understood.
    pub fn name(self: Entry) []const u8 {
        inline for (@typeInfo(Type3Opcode).@"enum".fields) |field| {
            if (field.value == self.opcode) return field.name;
        }
        return "<unnamed>";
    }
};

pub const Verdict = enum(u8) {
    /// No packet has been observed at all.
    no_packets,
    /// Packets were consumed and none of them asks for a completion. The title
    /// is not waiting on the GPU to report back.
    no_completion_requested,
    /// The title asked for a completion by interrupt and no interrupt with that
    /// source has reached the guest.
    interrupt_requested_not_delivered,
    /// The title asked for a completion by memory write and nothing has been
    /// observed writing it.
    memory_completion_requested_not_delivered,
    /// The title asked and something was delivered.
    completion_delivered,

    pub fn label(self: Verdict) []const u8 {
        return switch (self) {
            .no_packets => "no_packets",
            .no_completion_requested => "no_completion_requested",
            .interrupt_requested_not_delivered => "INTERRUPT_REQUESTED_NOT_DELIVERED",
            .memory_completion_requested_not_delivered => "MEMORY_COMPLETION_REQUESTED_NOT_DELIVERED",
            .completion_delivered => "completion_delivered",
        };
    }

    pub fn actionable(self: Verdict) bool {
        return self == .interrupt_requested_not_delivered or
            self == .memory_completion_requested_not_delivered;
    }

    pub fn describe(self: Verdict) []const u8 {
        return switch (self) {
            .no_packets => "no PM4 packet has been observed, so nothing here says anything about what the title asked for",
            .no_completion_requested => "the title's batch contains no interrupt and no event-write packet, so it never asked the GPU to tell it anything. A title parked after this batch is waiting on something that is not GPU completion, and looking for a missing interrupt is looking for something nobody requested — the wait's own object and guest call site are where that investigation goes instead",
            .interrupt_requested_not_delivered => "the title encoded a PM4 interrupt packet and no graphics interrupt with that source has reached the guest. The title asked to be told its batch finished and was not told. This is the emulator's, and the place to look is the interrupt packet handler and whether its dispatch reaches the callback the title registered",
            .memory_completion_requested_not_delivered => "the title encoded an event-write packet and nothing has been observed writing the value back. The title is polling memory that will never change",
            .completion_delivered => "the title asked for a completion and one was delivered. If it is still waiting, it is waiting on something else",
        };
    }
};

pub const Summary = struct {
    distinct: u8 = 0,
    packets: u64 = 0,
    draws: u64 = 0,
    blocking: u64 = 0,
    completion_requests: u64 = 0,
    interrupt_requests: u64 = 0,
    emulator_extensions: u64 = 0,
    unnamed: u64 = 0,
    dropped: u64 = 0,
};

pub const Ledger = struct {
    entries: [capacity]Entry = [_]Entry{.{}} ** capacity,
    count: usize = 0,
    dropped: u64 = 0,
    /// Graphics interrupts observed reaching the guest, by source. Source 0 is
    /// vblank; source 1 is the command stream's own interrupt packet. Indexed
    /// by source because "an interrupt fired" and "the interrupt the title
    /// asked for fired" are different facts, and every previous report had only
    /// the first.
    interrupts_by_source: [8]u64 = [_]u64{0} ** 8,
    /// Event-write values observed landing in guest memory.
    memory_completions_delivered: u64 = 0,
    /// The emulator's own census of what its command processor dispatched.
    ///
    /// A second, independent input rather than a replacement. Rosette's walk
    /// can see packets the emulator skipped for predication; the emulator's
    /// dispatch can see packets Rosette never scanned — and on the run this was
    /// written for Rosette's stateful executor was unarmed, so its histogram was
    /// empty while seventy-two packets had been dispatched. A verdict computed
    /// from only one of them would have been confidently wrong.
    emulator_packets: u64 = 0,
    emulator_interrupt_requests: u64 = 0,
    emulator_event_write_requests: u64 = 0,
    /// Committed completions whose value was not visible through the guest's
    /// other alias of the same page. Delivered to the emulator and not to the
    /// title, which is a different failure from not being written at all.
    memory_completion_alias_mismatches: u64 = 0,
    /// Graphics interrupts entered into guest code, and how many came back.
    ///
    /// The difference is the finding. `processor_->Execute` runs guest code on
    /// the calling thread, so a handler that blocks takes the frame limiter
    /// thread with it — the display pump dies inside the guest with its last
    /// recorded event being a successful entry. An entry count on its own
    /// cannot tell a handler that ran a hundred and fifty times from one that
    /// ran a hundred and forty-nine and is still inside the hundred and
    /// fiftieth.
    interrupt_dispatch_entered: u64 = 0,
    interrupt_dispatch_returned: u64 = 0,
    /// Vblanks raised by the wall-clock floor rather than by the guest clock.
    /// A non-zero count means the guest clock is not pacing the display and
    /// every deadline the title computes from it is stretched.
    vblank_floor_raises: u64 = 0,

    pub fn observeMemoryCompletionAliasMismatch(self: *Ledger) void {
        self.memory_completion_alias_mismatches +|= 1;
    }

    pub fn observeInterruptDispatchEntered(self: *Ledger, id: u64) void {
        if (id > self.interrupt_dispatch_entered) self.interrupt_dispatch_entered = id;
    }

    pub fn observeInterruptDispatchReturned(self: *Ledger, returned: u64) void {
        if (returned > self.interrupt_dispatch_returned) {
            self.interrupt_dispatch_returned = returned;
        }
    }

    pub fn observeVblankFloorRaise(self: *Ledger) void {
        self.vblank_floor_raises +|= 1;
    }

    /// Dispatches that entered guest code and have not come back.
    ///
    /// One outstanding is normal — a dispatch in flight at the moment the log
    /// line was written. More than one, or one that stays outstanding across
    /// checkpoints, means a guest handler is not returning and the thread that
    /// entered it is gone.
    pub fn outstandingInterruptDispatches(self: *const Ledger) u64 {
        return self.interrupt_dispatch_entered -| self.interrupt_dispatch_returned;
    }

    /// Counts straight from the emulator's type-3 dispatch. Monotonic: a later
    /// census supersedes an earlier one rather than adding to it.
    pub fn observeEmulatorCounts(
        self: *Ledger,
        packets: u64,
        interrupt_requests: u64,
        event_write_requests: u64,
    ) void {
        if (packets > self.emulator_packets) self.emulator_packets = packets;
        if (interrupt_requests > self.emulator_interrupt_requests) {
            self.emulator_interrupt_requests = interrupt_requests;
        }
        if (event_write_requests > self.emulator_event_write_requests) {
            self.emulator_event_write_requests = event_write_requests;
        }
    }

    pub fn observePacket(self: *Ledger, opcode: u8, step: u64) void {
        for (self.entries[0..self.count]) |*entry| {
            if (entry.opcode != opcode) continue;
            entry.count +|= 1;
            if (step > entry.last_step) entry.last_step = step;
            return;
        }
        if (self.count >= capacity) {
            self.dropped +|= 1;
            return;
        }
        self.entries[self.count] = .{
            .opcode = opcode,
            .count = 1,
            .first_step = step,
            .last_step = step,
        };
        self.count += 1;
    }

    /// A graphics interrupt reached the guest with this source.
    pub fn observeInterruptDelivered(self: *Ledger, source: u32) void {
        const index = if (source < self.interrupts_by_source.len) source else 0;
        self.interrupts_by_source[index] +|= 1;
    }

    pub fn observeMemoryCompletionDelivered(self: *Ledger) void {
        self.memory_completions_delivered +|= 1;
    }

    pub fn observed(self: *const Ledger) []const Entry {
        return self.entries[0..self.count];
    }

    pub fn countOf(self: *const Ledger, opcode: Type3Opcode) u64 {
        for (self.entries[0..self.count]) |entry| {
            if (entry.opcode == @intFromEnum(opcode)) return entry.count;
        }
        return 0;
    }

    pub fn summary(self: *const Ledger) Summary {
        var out = Summary{ .dropped = self.dropped };
        for (self.entries[0..self.count]) |entry| {
            out.distinct += 1;
            out.packets +|= entry.count;
            const typed = entry.typed();
            if (typed.isDraw()) out.draws +|= entry.count;
            if (typed.isBlocking()) out.blocking +|= entry.count;
            if (typed.requestsCompletion()) out.completion_requests +|= entry.count;
            if (typed.requestsInterrupt()) out.interrupt_requests +|= entry.count;
            if (typed.isEmulatorExtension()) out.emulator_extensions +|= entry.count;
            if (!isNamed(entry.opcode)) out.unnamed +|= entry.count;
        }
        return out;
    }

    /// Interrupts delivered with the source the command stream's own interrupt
    /// packet uses. Kept separate from the total because vblank interrupts fire
    /// on their own schedule and would mask a completion that never arrived.
    pub fn commandStreamInterrupts(self: *const Ledger) u64 {
        return self.interrupts_by_source[1];
    }

    pub fn verdict(self: *const Ledger) Verdict {
        const totals = self.summary();
        // Whichever observer saw more packets is the one with something to say.
        // Taking the maximum rather than one source keeps a verdict from being
        // computed off an empty histogram while the other input holds seventy-
        // two dispatched packets.
        const packets = @max(totals.packets, self.emulator_packets);
        if (packets == 0) return .no_packets;
        const interrupt_requests = @max(
            totals.interrupt_requests,
            self.emulator_interrupt_requests,
        );
        const memory_requests = @max(
            totals.completion_requests -| totals.interrupt_requests,
            self.emulator_event_write_requests,
        );
        if (interrupt_requests == 0 and memory_requests == 0) {
            return .no_completion_requested;
        }
        if (interrupt_requests != 0 and self.commandStreamInterrupts() == 0) {
            return .interrupt_requested_not_delivered;
        }
        if (memory_requests != 0 and self.memory_completions_delivered == 0) {
            return .memory_completion_requested_not_delivered;
        }
        return .completion_delivered;
    }
};

/// Whether the opcode is one the contract names. An unnamed opcode is not an
/// error — the console's space is wider than the emulator's table — but a batch
/// full of them means the census is describing something it does not
/// understand, and saying so is better than presenting the numbers as complete.
fn isNamed(opcode: u8) bool {
    inline for (@typeInfo(Type3Opcode).@"enum".fields) |field| {
        if (field.value == opcode) return true;
    }
    return false;
}

test "an empty census says nothing" {
    const ledger = Ledger{};
    try std.testing.expectEqual(Verdict.no_packets, ledger.verdict());
    try std.testing.expectEqual(@as(u64, 0), ledger.summary().packets);
}

// The batch shape from 2026-08-31: draws and state, no completion request. A
// title parked after this is not waiting on the GPU.
test "a batch with no completion packet says the title never asked" {
    var ledger = Ledger{};
    var draw: u64 = 0;
    while (draw < 24) : (draw += 1) {
        ledger.observePacket(@intFromEnum(Type3Opcode.draw_indx_2), 3_399_870_297 + draw);
    }
    ledger.observePacket(@intFromEnum(Type3Opcode.set_constant), 3_390_782_223);
    ledger.observePacket(@intFromEnum(Type3Opcode.indirect_buffer), 3_390_745_780);

    const totals = ledger.summary();
    try std.testing.expectEqual(@as(u64, 24), totals.draws);
    try std.testing.expectEqual(@as(u64, 0), totals.completion_requests);
    try std.testing.expectEqual(Verdict.no_completion_requested, ledger.verdict());
    // Not actionable: it is a redirection, not a defect. The investigation moves
    // to the wait's own object rather than to a missing interrupt.
    try std.testing.expect(!ledger.verdict().actionable());
}

// The opposite explanation for the same stall, and the one that names the
// emulator.
test "an interrupt packet with no source-1 delivery is the emulator's" {
    var ledger = Ledger{};
    ledger.observePacket(@intFromEnum(Type3Opcode.draw_indx_2), 100);
    ledger.observePacket(@intFromEnum(Type3Opcode.interrupt), 200);
    // Vblank interrupts keep arriving and must not mask the missing completion.
    var vblank: u64 = 0;
    while (vblank < 720) : (vblank += 1) ledger.observeInterruptDelivered(0);

    try std.testing.expectEqual(
        Verdict.interrupt_requested_not_delivered,
        ledger.verdict(),
    );
    try std.testing.expect(ledger.verdict().actionable());
    try std.testing.expectEqual(@as(u64, 0), ledger.commandStreamInterrupts());

    ledger.observeInterruptDelivered(1);
    try std.testing.expectEqual(Verdict.completion_delivered, ledger.verdict());
}

test "an event write with nothing written back is a memory completion gap" {
    var ledger = Ledger{};
    ledger.observePacket(@intFromEnum(Type3Opcode.event_write_shd), 100);
    try std.testing.expectEqual(
        Verdict.memory_completion_requested_not_delivered,
        ledger.verdict(),
    );
    ledger.observeMemoryCompletionDelivered();
    try std.testing.expectEqual(Verdict.completion_delivered, ledger.verdict());
}

test "repeated opcodes collapse into one entry with a count" {
    var ledger = Ledger{};
    var index: u64 = 0;
    while (index < 50) : (index += 1) {
        ledger.observePacket(@intFromEnum(Type3Opcode.nop), 1_000 + index);
    }
    try std.testing.expectEqual(@as(usize, 1), ledger.count);
    try std.testing.expectEqual(@as(u64, 50), ledger.countOf(.nop));
    try std.testing.expectEqual(@as(u64, 1_000), ledger.observed()[0].first_step);
    try std.testing.expectEqual(@as(u64, 1_049), ledger.observed()[0].last_step);
}

// An opcode the contract does not name is not an error, and a census full of
// them is describing something it does not understand.
test "unnamed opcodes are counted rather than hidden" {
    var ledger = Ledger{};
    ledger.observePacket(0x7E, 10);
    try std.testing.expectEqual(@as(u64, 1), ledger.summary().unnamed);
    try std.testing.expectEqual(@as(u64, 0), ledger.summary().draws);
}

test "opcodes past capacity are counted rather than discarded" {
    var ledger = Ledger{};
    var opcode: u64 = 0;
    while (opcode < capacity + 6) : (opcode += 1) {
        ledger.observePacket(@intCast(opcode), opcode);
    }
    try std.testing.expectEqual(capacity, ledger.count);
    try std.testing.expectEqual(@as(u64, 6), ledger.summary().dropped);
}

test "blocking packets are counted, because a ring parks on one of them" {
    var ledger = Ledger{};
    ledger.observePacket(@intFromEnum(Type3Opcode.wait_reg_mem), 10);
    ledger.observePacket(@intFromEnum(Type3Opcode.wait_for_idle), 20);
    try std.testing.expectEqual(@as(u64, 2), ledger.summary().blocking);
}

test "every verdict explains itself" {
    inline for (@typeInfo(Verdict).@"enum".fields) |field| {
        const value: Verdict = @enumFromInt(field.value);
        try std.testing.expect(value.label().len != 0);
        try std.testing.expect(value.describe().len != 0);
    }
}

test "an entry names its opcode, and says so when it cannot" {
    const known = Entry{ .opcode = @intFromEnum(Type3Opcode.interrupt) };
    try std.testing.expectEqualStrings("interrupt", known.name());
    const unknown = Entry{ .opcode = 0x7E };
    try std.testing.expectEqualStrings("<unnamed>", unknown.name());
}

// Rosette's stateful executor was unarmed on the 2026-08-31 run, so its own
// histogram was empty while the command processor had dispatched seventy-two
// packets. A verdict from only one input would have said `no_packets`.
test "the emulator's census answers when Rosette's own walk saw nothing" {
    var ledger = Ledger{};
    try std.testing.expectEqual(Verdict.no_packets, ledger.verdict());
    ledger.observeEmulatorCounts(72, 0, 0);
    try std.testing.expectEqual(Verdict.no_completion_requested, ledger.verdict());
    ledger.observeEmulatorCounts(90, 1, 0);
    try std.testing.expectEqual(Verdict.interrupt_requested_not_delivered, ledger.verdict());
    ledger.observeInterruptDelivered(1);
    try std.testing.expectEqual(Verdict.completion_delivered, ledger.verdict());
}

test "an emulator census only ever advances" {
    var ledger = Ledger{};
    ledger.observeEmulatorCounts(90, 2, 1);
    ledger.observeEmulatorCounts(4, 0, 0);
    try std.testing.expectEqual(@as(u64, 90), ledger.emulator_packets);
    try std.testing.expectEqual(@as(u64, 2), ledger.emulator_interrupt_requests);
    try std.testing.expectEqual(@as(u64, 1), ledger.emulator_event_write_requests);
}

// The false accusation this fixes: a title that asked for two event writes and
// got both of them read as never delivered, because nothing parsed the commit.
test "a committed memory completion clears the request" {
    var ledger = Ledger{};
    ledger.observeEmulatorCounts(72, 0, 2);
    try std.testing.expectEqual(
        Verdict.memory_completion_requested_not_delivered,
        ledger.verdict(),
    );
    ledger.observeMemoryCompletionDelivered();
    try std.testing.expectEqual(Verdict.completion_delivered, ledger.verdict());
}

// A value written to one alias and not visible through the other is delivered
// to the emulator and not to the guest, which is a different failure from not
// being written at all.
test "an alias mismatch is counted apart from the delivery" {
    var ledger = Ledger{};
    ledger.observeMemoryCompletionDelivered();
    ledger.observeMemoryCompletionAliasMismatch();
    try std.testing.expectEqual(@as(u64, 1), ledger.memory_completions_delivered);
    try std.testing.expectEqual(@as(u64, 1), ledger.memory_completion_alias_mismatches);
}

// `processor_->Execute` runs guest code on the calling thread, so a handler
// that blocks takes the frame limiter with it. Only the entry/return
// difference can see that.
test "an interrupt dispatch that never returns is outstanding" {
    var ledger = Ledger{};
    ledger.observeInterruptDispatchEntered(150);
    ledger.observeInterruptDispatchReturned(149);
    try std.testing.expectEqual(@as(u64, 1), ledger.outstandingInterruptDispatches());
    ledger.observeInterruptDispatchReturned(150);
    try std.testing.expectEqual(@as(u64, 0), ledger.outstandingInterruptDispatches());
}

test "dispatch counters only advance" {
    var ledger = Ledger{};
    ledger.observeInterruptDispatchEntered(150);
    ledger.observeInterruptDispatchEntered(4);
    try std.testing.expectEqual(@as(u64, 150), ledger.interrupt_dispatch_entered);
}
