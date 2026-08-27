//! Who waits on what, who signals it, and whether the handshake is going
//! anywhere.
//!
//! The livelock predictor already reports the shape:
//!
//! ```text
//! op=wait              object=0x333dec14 thread=0x7fff2160 count=1212
//! op=release_semaphore object=0x333dec14 thread=0x7fff2150 count=1218
//! op=set_event         object=0x333dec28 thread=0x7fff2150 count=1217
//! ```
//!
//! What it cannot say is who is on which end. Twelve hundred matched waits and
//! releases with nothing parked and nothing unsignalled passes every deadlock
//! check in the process, because by their question it is healthy. The pair is
//! alive, both threads are running, and the run is not moving.
//!
//! This builds the other half: a per-object waiter/signaller set, so a stalled
//! handshake names *which thread waits* and *which thread feeds it*, and a
//! bounded cycle check that finds two threads each waiting on an object only
//! the other signals.
//!
//! ## The progress gate is not optional
//!
//! Two threads passing a semaphore is what a working producer/consumer pair
//! looks like. The counters are identical to a livelocked one. Every verdict
//! here is therefore gated on an independent progress axis the caller supplies,
//! because a predictor that reports healthy worker loops as livelocks trains a
//! reader to skip the line that eventually matters.
//!
//! ## Identity is the hazard
//!
//! The same object appears as `0x333dec14`, `0x827CEC14` and `0xD1BBEC14` in
//! three different reports. Waits recorded under one name and signals under
//! another produce a phantom orphan wait next to a phantom orphan signal, which
//! is exactly the pair of findings that sends an investigation in two wrong
//! directions at once. The ledger folds addresses through a caller-supplied
//! canonical form and counts how often it had to.

const std = @import("std");
const contract = @import("xenia_wait_graph_contract");

pub const Role = contract.Role;
pub const PairState = contract.PairState;
pub const Verdict = contract.Verdict;

/// Bounded, because this is fed from the guest wait path. A run with more
/// distinct sync objects than this reports the overflow rather than evicting:
/// a table that follows the most recent object makes the verdict follow it too.
pub const max_objects: usize = 64;
pub const max_participants: usize = 8;

pub const Participant = struct {
    thread: u64 = 0,
    /// Guest program counter of the most recent operation, so a reader can go
    /// straight to the call site rather than searching for it.
    pc: u64 = 0,
    events: u64 = 0,
    first_step: u64 = 0,
    last_step: u64 = 0,
};

pub const ObjectRecord = struct {
    address: u64 = 0,
    occupied: bool = false,

    waits: u64 = 0,
    signals: u64 = 0,
    waiters: [max_participants]Participant = [_]Participant{.{}} ** max_participants,
    waiter_count: usize = 0,
    signallers: [max_participants]Participant = [_]Participant{.{}} ** max_participants,
    signaller_count: usize = 0,
    /// Participants that did not fit. Counted so a crowded object is not
    /// mistaken for a simple one.
    participants_dropped: u64 = 0,

    first_step: u64 = 0,
    last_step: u64 = 0,
    /// Value of the caller's progress axis when this object was first seen, so
    /// the classifier can ask whether anything moved *while it cycled* rather
    /// than whether anything ever moved.
    progress_at_first: u64 = 0,
    progress_at_last: u64 = 0,

    pub fn state(self: ObjectRecord) PairState {
        return contract.classifyPair(
            self.waits,
            self.signals,
            self.progress_at_last > self.progress_at_first,
        );
    }

    /// The thread doing the waiting, when exactly one does. A stalled handshake
    /// with a single waiter names the thread to look at; one with several is a
    /// different and harder shape, and saying so is better than picking one.
    pub fn soleWaiter(self: ObjectRecord) ?Participant {
        if (self.waiter_count != 1) return null;
        return self.waiters[0];
    }

    pub fn soleSignaller(self: ObjectRecord) ?Participant {
        if (self.signaller_count != 1) return null;
        return self.signallers[0];
    }
};

pub const Cycle = struct {
    first_thread: u64 = 0,
    second_thread: u64 = 0,
    first_object: u64 = 0,
    second_object: u64 = 0,
};

pub const Summary = struct {
    objects: usize = 0,
    dropped_objects: u64 = 0,
    orphan_waits: usize = 0,
    orphan_signals: usize = 0,
    stalled_handshakes: usize = 0,
    progressing_handshakes: usize = 0,
    insufficient: usize = 0,
    cycles: usize = 0,
    events: u64 = 0,
    canonical_folds: u64 = 0,
    cycle: ?Cycle = null,

    pub fn verdict(self: Summary) Verdict {
        return contract.verdictOf(
            self.objects,
            self.orphan_waits,
            self.orphan_signals,
            self.stalled_handshakes,
            self.cycles,
        );
    }
};

/// Folds an observed address to the identity the ledger keys on. Supplied by
/// the caller because only the process knows the host/guest projections; the
/// ledger only knows that it must not key on two names for one object.
pub const CanonicalFn = *const fn (address: u64) u64;

pub const Ledger = struct {
    objects: [max_objects]ObjectRecord = [_]ObjectRecord{.{}} ** max_objects,
    occupied: usize = 0,
    dropped_objects: u64 = 0,
    events: u64 = 0,
    canonical_folds: u64 = 0,
    canonical: ?CanonicalFn = null,

    /// The independent progress axis. Any counter that a spin cannot advance:
    /// milestones reached, ring publications, guest output frames. Compared
    /// against itself over time, never interpreted.
    progress: u64 = 0,

    pub fn setCanonical(self: *Ledger, canonical: CanonicalFn) void {
        self.canonical = canonical;
    }

    /// Update the axis the classifier gates on. Callers push rather than the
    /// ledger pulling, so the ledger has no opinion about what progress means.
    pub fn noteProgress(self: *Ledger, value: u64) void {
        if (value > self.progress) self.progress = value;
    }

    fn canonicalise(self: *Ledger, address: u64) u64 {
        const fold = self.canonical orelse return address;
        const folded = fold(address);
        if (folded != address) self.canonical_folds +|= 1;
        return folded;
    }

    fn slot(self: *Ledger, address: u64) ?*ObjectRecord {
        const mask = max_objects - 1;
        var index: usize = @intCast(address % max_objects);
        var probes: usize = 0;
        while (probes < max_objects) : (probes += 1) {
            const entry = &self.objects[index];
            if (!entry.occupied) return entry;
            if (entry.address == address) return entry;
            index = (index + 1) & mask;
        }
        return null;
    }

    fn recordParticipant(
        list: *[max_participants]Participant,
        count: *usize,
        dropped: *u64,
        thread: u64,
        pc: u64,
        step: u64,
    ) void {
        for (list[0..count.*]) |*existing| {
            if (existing.thread != thread) continue;
            existing.events +|= 1;
            existing.last_step = step;
            existing.pc = pc;
            return;
        }
        if (count.* == max_participants) {
            dropped.* +|= 1;
            return;
        }
        list[count.*] = .{
            .thread = thread,
            .pc = pc,
            .events = 1,
            .first_step = step,
            .last_step = step,
        };
        count.* += 1;
    }

    pub fn observe(
        self: *Ledger,
        role: Role,
        address: u64,
        thread: u64,
        pc: u64,
        step: u64,
    ) void {
        if (address == 0) return;
        self.events +|= 1;
        const key = self.canonicalise(address);
        const entry = self.slot(key) orelse {
            self.dropped_objects +|= 1;
            return;
        };
        if (!entry.occupied) {
            entry.* = .{
                .address = key,
                .occupied = true,
                .first_step = step,
                .progress_at_first = self.progress,
            };
            self.occupied += 1;
        }
        entry.last_step = step;
        entry.progress_at_last = self.progress;
        switch (role) {
            .waiter => {
                entry.waits +|= 1;
                recordParticipant(
                    &entry.waiters,
                    &entry.waiter_count,
                    &entry.participants_dropped,
                    thread,
                    pc,
                    step,
                );
            },
            .signaller => {
                entry.signals +|= 1;
                recordParticipant(
                    &entry.signallers,
                    &entry.signaller_count,
                    &entry.participants_dropped,
                    thread,
                    pc,
                    step,
                );
            },
        }
    }

    pub fn record(self: *const Ledger, address: u64) ?ObjectRecord {
        for (self.objects) |entry| {
            if (entry.occupied and entry.address == address) return entry;
        }
        return null;
    }

    /// Two threads each waiting on an object only the other signals.
    ///
    /// Bounded to pairs on purpose. A longer chain is possible in principle and
    /// has never appeared in this system, and an unbounded search over a table
    /// written from the guest wait path is a cost with no demonstrated payoff.
    /// A pair is the shape that actually occurs, and reporting it precisely
    /// beats reporting a general cycle vaguely.
    pub fn findCycle(self: *const Ledger) ?Cycle {
        for (self.objects) |first| {
            if (!first.occupied) continue;
            const first_waiter = first.soleWaiter() orelse continue;
            const first_signaller = first.soleSignaller() orelse continue;
            if (first_waiter.thread == first_signaller.thread) continue;

            for (self.objects) |second| {
                if (!second.occupied or second.address == first.address) continue;
                const second_waiter = second.soleWaiter() orelse continue;
                const second_signaller = second.soleSignaller() orelse continue;
                // A waits on X that only B signals; B waits on Y that only A
                // signals.
                if (second_waiter.thread == first_signaller.thread and
                    second_signaller.thread == first_waiter.thread)
                {
                    return .{
                        .first_thread = first_waiter.thread,
                        .second_thread = second_waiter.thread,
                        .first_object = first.address,
                        .second_object = second.address,
                    };
                }
            }
        }
        return null;
    }

    pub fn summary(self: *const Ledger) Summary {
        var totals = Summary{
            .objects = self.occupied,
            .dropped_objects = self.dropped_objects,
            .events = self.events,
            .canonical_folds = self.canonical_folds,
        };
        for (self.objects) |entry| {
            if (!entry.occupied) continue;
            switch (entry.state()) {
                .wait_never_signalled => totals.orphan_waits += 1,
                .signal_never_waited => totals.orphan_signals += 1,
                .handshake_stalled => totals.stalled_handshakes += 1,
                .handshake_progressing => totals.progressing_handshakes += 1,
                .insufficient_sample => totals.insufficient += 1,
                .unobserved => {},
            }
        }
        if (self.findCycle()) |cycle| {
            totals.cycles = 1;
            totals.cycle = cycle;
        }
        return totals;
    }

    /// The object a reader should look at first: a cycle member, then a stalled
    /// handshake, then an orphan wait, ordered by how little a longer run can
    /// do about it.
    pub fn blocking(self: *const Ledger) ?ObjectRecord {
        var best: ?ObjectRecord = null;
        var best_rank: u8 = 0;
        for (self.objects) |entry| {
            if (!entry.occupied) continue;
            const rank: u8 = switch (entry.state()) {
                .handshake_stalled => 3,
                .wait_never_signalled => 2,
                .signal_never_waited => 1,
                else => 0,
            };
            if (rank == 0) continue;
            // Among equals prefer the busiest: a pair that has gone round a
            // thousand times is a stronger finding than one that has gone
            // round nine.
            const better = rank > best_rank or
                (rank == best_rank and best != null and
                    entry.waits + entry.signals > best.?.waits + best.?.signals);
            if (best == null or better) {
                best = entry;
                best_rank = rank;
            }
        }
        return best;
    }
};

fn foldLowBits(address: u64) u64 {
    // Test double for the real projection fold: three names for one object
    // share their low bits.
    return address & 0xFFFF;
}

test "the live shape: a matched handshake with nothing else moving" {
    // 1212 waits from one thread, 1218 releases from another, progress flat.
    var ledger = Ledger{};
    var round: u64 = 0;
    while (round < 40) : (round += 1) {
        ledger.observe(.signaller, 0x333d_ec14, 0x7fff_2150, 0x1bd9d0, round * 10);
        ledger.observe(.waiter, 0x333d_ec14, 0x7fff_2160, 0x1bd7c0, round * 10 + 1);
    }

    const record = ledger.record(0x333d_ec14).?;
    try std.testing.expectEqual(PairState.handshake_stalled, record.state());
    try std.testing.expectEqual(@as(u64, 0x7fff_2160), record.soleWaiter().?.thread);
    try std.testing.expectEqual(@as(u64, 0x7fff_2150), record.soleSignaller().?.thread);
    // The call sites, so a reader goes straight there.
    try std.testing.expectEqual(@as(u64, 0x1bd7c0), record.soleWaiter().?.pc);
    try std.testing.expectEqual(@as(u64, 0x1bd9d0), record.soleSignaller().?.pc);

    const totals = ledger.summary();
    try std.testing.expectEqual(@as(usize, 1), totals.stalled_handshakes);
    try std.testing.expectEqual(Verdict.handshake_without_progress, totals.verdict());
    try std.testing.expect(!totals.verdict().selfResolving());
}

test "the same handshake stops being a finding when progress advances" {
    // The gate. Without it every healthy worker loop reads as a livelock.
    var ledger = Ledger{};
    var round: u64 = 0;
    while (round < 40) : (round += 1) {
        ledger.noteProgress(round);
        ledger.observe(.signaller, 0x333d_ec14, 0x7fff_2150, 0x1bd9d0, round * 10);
        ledger.observe(.waiter, 0x333d_ec14, 0x7fff_2160, 0x1bd7c0, round * 10 + 1);
    }
    const totals = ledger.summary();
    try std.testing.expectEqual(@as(usize, 0), totals.stalled_handshakes);
    try std.testing.expectEqual(@as(usize, 1), totals.progressing_handshakes);
    try std.testing.expectEqual(Verdict.healthy, totals.verdict());
}

test "two threads each waiting on the other's object is a cycle" {
    var ledger = Ledger{};
    var round: u64 = 0;
    while (round < 12) : (round += 1) {
        // Thread A waits on X, thread B signals X.
        ledger.observe(.waiter, 0x1000, 0xAAAA, 0x10, round);
        ledger.observe(.signaller, 0x1000, 0xBBBB, 0x20, round);
        // Thread B waits on Y, thread A signals Y.
        ledger.observe(.waiter, 0x2000, 0xBBBB, 0x30, round);
        ledger.observe(.signaller, 0x2000, 0xAAAA, 0x40, round);
    }
    const totals = ledger.summary();
    try std.testing.expectEqual(@as(usize, 1), totals.cycles);
    try std.testing.expectEqual(Verdict.wait_cycle, totals.verdict());
    const cycle = totals.cycle.?;
    try std.testing.expect(cycle.first_thread != cycle.second_thread);
    try std.testing.expect(cycle.first_object != cycle.second_object);
}

test "an orphan wait and an orphan signal are kept apart" {
    var ledger = Ledger{};
    var round: u64 = 0;
    while (round < 12) : (round += 1) {
        ledger.observe(.waiter, 0x3000, 0xAAAA, 0x10, round);
        ledger.observe(.signaller, 0x4000, 0xBBBB, 0x20, round);
    }
    const totals = ledger.summary();
    try std.testing.expectEqual(@as(usize, 1), totals.orphan_waits);
    try std.testing.expectEqual(@as(usize, 1), totals.orphan_signals);
    // The orphan wait is the stall; the orphan signal says the consumer is
    // elsewhere. The verdict reports the one a longer run cannot fix.
    try std.testing.expectEqual(Verdict.orphan_wait, totals.verdict());
    try std.testing.expectEqual(@as(u64, 0x3000), ledger.blocking().?.address);
}

test "one object under three names is folded into one identity" {
    // Waits under one address and signals under another manufacture a phantom
    // orphan wait beside a phantom orphan signal — two wrong findings at once.
    var ledger = Ledger{};
    ledger.setCanonical(foldLowBits);
    var round: u64 = 0;
    while (round < 12) : (round += 1) {
        ledger.observe(.waiter, 0x333d_ec14, 0xAAAA, 0x10, round);
        ledger.observe(.signaller, 0x827c_ec14, 0xBBBB, 0x20, round);
        ledger.observe(.signaller, 0xd1bb_ec14, 0xBBBB, 0x20, round);
    }
    const totals = ledger.summary();
    try std.testing.expectEqual(@as(usize, 1), totals.objects);
    try std.testing.expectEqual(@as(usize, 0), totals.orphan_waits);
    try std.testing.expectEqual(@as(usize, 0), totals.orphan_signals);
    try std.testing.expectEqual(@as(usize, 1), totals.stalled_handshakes);
    try std.testing.expect(totals.canonical_folds != 0);
}

test "without a fold the same three names look like three broken objects" {
    // The counterpart: this is what the report says when identity is wrong,
    // and it is why the fold is worth its cost.
    var ledger = Ledger{};
    var round: u64 = 0;
    while (round < 12) : (round += 1) {
        ledger.observe(.waiter, 0x333d_ec14, 0xAAAA, 0x10, round);
        ledger.observe(.signaller, 0x827c_ec14, 0xBBBB, 0x20, round);
    }
    const totals = ledger.summary();
    try std.testing.expectEqual(@as(usize, 2), totals.objects);
    try std.testing.expectEqual(@as(usize, 1), totals.orphan_waits);
    try std.testing.expectEqual(@as(usize, 1), totals.orphan_signals);
    try std.testing.expectEqual(@as(u64, 0), totals.canonical_folds);
}

test "several waiters on one object is reported rather than guessed at" {
    var ledger = Ledger{};
    var round: u64 = 0;
    while (round < 12) : (round += 1) {
        ledger.observe(.waiter, 0x5000, 0xAAAA, 0x10, round);
        ledger.observe(.waiter, 0x5000, 0xCCCC, 0x11, round);
        ledger.observe(.signaller, 0x5000, 0xBBBB, 0x20, round);
    }
    const record = ledger.record(0x5000).?;
    try std.testing.expectEqual(@as(usize, 2), record.waiter_count);
    // Naming one of two waiters would send a reader to a coin flip.
    try std.testing.expect(record.soleWaiter() == null);
    try std.testing.expectEqual(@as(u64, 0xBBBB), record.soleSignaller().?.thread);
    // A crowd is not a cycle.
    try std.testing.expect(ledger.findCycle() == null);
}

test "the busiest stalled handshake is the one reported" {
    var ledger = Ledger{};
    var round: u64 = 0;
    while (round < 10) : (round += 1) {
        ledger.observe(.waiter, 0x6000, 0xAAAA, 0x10, round);
        ledger.observe(.signaller, 0x6000, 0xBBBB, 0x20, round);
    }
    round = 0;
    while (round < 400) : (round += 1) {
        ledger.observe(.waiter, 0x7000, 0xCCCC, 0x30, round);
        ledger.observe(.signaller, 0x7000, 0xDDDD, 0x40, round);
    }
    try std.testing.expectEqual(@as(u64, 0x7000), ledger.blocking().?.address);
}

test "a full table counts the overflow rather than evicting" {
    var ledger = Ledger{};
    var index: u64 = 1;
    while (index <= max_objects + 6) : (index += 1) {
        ledger.observe(.waiter, index * 0x1000, 0xAAAA, 0x10, index);
    }
    try std.testing.expectEqual(max_objects, ledger.summary().objects);
    try std.testing.expect(ledger.summary().dropped_objects != 0);
}

test "an empty graph concludes nothing" {
    const ledger = Ledger{};
    const totals = ledger.summary();
    try std.testing.expectEqual(Verdict.idle, totals.verdict());
    try std.testing.expect(ledger.blocking() == null);
    try std.testing.expect(ledger.findCycle() == null);
    try std.testing.expect(std.mem.indexOf(u8, totals.verdict().guidance(), "nothing can be said") != null);
}

test "participants beyond the retained set are counted" {
    var ledger = Ledger{};
    var thread: u64 = 1;
    while (thread <= max_participants + 3) : (thread += 1) {
        ledger.observe(.waiter, 0x8000, thread, 0x10, thread);
    }
    const record = ledger.record(0x8000).?;
    try std.testing.expectEqual(max_participants, record.waiter_count);
    try std.testing.expectEqual(@as(u64, 3), record.participants_dropped);
}
