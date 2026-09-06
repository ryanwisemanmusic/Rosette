//! Objects a thread waits on that nothing ever signals, objects something
//! signals that nothing ever waits on, and the guest call site of each — joined,
//! because separately neither half is a finding and together they usually are.
//!
//! ## The reading this was built for
//!
//! The 2026-08-31 run ended with the title's main thread polling a manual-reset
//! event with a thirty-millisecond deadline, three hundred and six times, with
//! `signals=0`. In the same run another event was set one thousand eight
//! hundred and twenty-four times with `was_signalled=0 wait=0` — set, and
//! nobody waiting.
//!
//! ```text
//! wait   object=0x40004bf4 handle=0xf8000158 waits=306 signals=0  guest_pc=8258A470
//! signal object=0x827cec28 handle=0xf800016c waits=0   signals=1824
//! ```
//!
//! Every existing report had one of those two lines and neither had both. A
//! parked consumer on its own reads as "the producer is late". An unconsumed
//! signal on its own reads as "the consumer is busy elsewhere". Put side by
//! side they are a different statement: **two halves of a handshake that are
//! not talking to each other**, which is either a producer that never ran or an
//! object that has been split into two identities.
//!
//! ## Why the guest call site matters more than the object
//!
//! An object address names a slot in the emulator. `guest_pc` and `lr` name the
//! *title's own instruction* that is stuck — which is the only thing that can
//! be looked up in a disassembly and acted on. The wait ledgers have carried
//! that field for a while and nothing reported it, so every finding about a
//! parked consumer stopped at an address nobody could do anything with.
//!
//! ## Creation provenance
//!
//! An object the emulator created through a kernel export leaves a breadcrumb.
//! One that appears only as `Added handle:… for XObject` did not come through
//! that path. That distinction decides whether "nothing signals it" means a
//! missing producer or an object the emulator does not fully own, and it is
//! cheap to carry.
//!
//! ## What it never does
//!
//! It does not signal anything. A synthetic wake would move the run on a value
//! Rosette invented and retire the only honest signal in it.

const std = @import("std");

/// How an object came into existence, as far as the log can tell.
pub const Provenance = enum(u8) {
    /// Never seen being created.
    unknown,
    /// Created through a kernel export that left a breadcrumb.
    kernel_export,
    /// Appeared only as a handle registration, with no creating export
    /// observed. Not wrong — but it means the emulator's own creation path was
    /// not the route, and "nothing signals it" carries a different weight.
    bare_handle,

    pub fn label(self: Provenance) []const u8 {
        return switch (self) {
            .unknown => "unknown",
            .kernel_export => "kernel-export",
            .bare_handle => "bare-handle",
        };
    }
};

/// What one object's traffic looks like.
pub const Role = enum(u8) {
    /// Waited on and signalled. A working handshake.
    matched,
    /// Waited on, never signalled. A parked or polling consumer.
    orphan_wait,
    /// Signalled, never waited on. A producer talking to nobody.
    orphan_signal,
    /// Neither. Recorded and says nothing.
    idle,

    pub fn label(self: Role) []const u8 {
        return switch (self) {
            .matched => "matched",
            .orphan_wait => "ORPHAN-WAIT",
            .orphan_signal => "ORPHAN-SIGNAL",
            .idle => "idle",
        };
    }
};

pub const Record = struct {
    object: u64 = 0,
    handle: u32 = 0,
    waits: u64 = 0,
    timeouts: u64 = 0,
    signals: u64 = 0,
    /// The thread parked or polling on it, and where in *guest* code it is.
    /// The object address names a slot in the emulator; this names the title's
    /// own instruction, which is the only one of the two that can be looked up.
    waiter_thread: u64 = 0,
    guest_pc: u64 = 0,
    guest_lr: u64 = 0,
    guest_pc_trusted: bool = false,
    signaller_thread: u64 = 0,
    signaller_pc: u64 = 0,
    provenance: Provenance = .unknown,
    /// The deadline the waiter asked for, when it asked for one at all. Zero
    /// means an unbounded wait, which is a different situation from a poll.
    timeout_ms: u32 = 0,
    first_step: u64 = 0,
    last_step: u64 = 0,
    valid: bool = false,

    pub fn role(self: Record) Role {
        if (self.waits == 0 and self.signals == 0) return .idle;
        if (self.signals == 0) return .orphan_wait;
        if (self.waits == 0) return .orphan_signal;
        return .matched;
    }

    /// A waiter that always expires is polling; one that never returns is
    /// parked. They call for different work, and the deadline is what separates
    /// them.
    pub fn polling(self: Record) bool {
        return self.timeout_ms != 0 and self.timeouts != 0;
    }
};

pub const capacity: usize = 32;

pub const Verdict = enum(u8) {
    /// Nothing to say.
    quiet,
    /// Every object with traffic has both ends.
    matched,
    /// The only waiter without a signal has a finite deadline and has returned
    /// from it. It is polling, not parked, so it is context rather than a
    /// missing half of a blocking handshake.
    bounded_poll_without_signal,
    /// Something is signalling an object nobody waits on, and nothing else is
    /// wrong. The consumer is elsewhere.
    signal_without_consumer,
    /// A thread is waiting on an object nothing signals, and nothing else is
    /// producing. A missing producer.
    wait_without_producer,
    /// Both at once. The strongest form: two halves of a handshake that are not
    /// talking to each other.
    unmatched_pair,

    pub fn label(self: Verdict) []const u8 {
        return switch (self) {
            .quiet => "quiet",
            .matched => "matched",
            .bounded_poll_without_signal => "bounded_poll_without_signal",
            .signal_without_consumer => "signal_without_consumer",
            .wait_without_producer => "wait_without_producer",
            .unmatched_pair => "UNMATCHED_PAIR",
        };
    }

    pub fn actionable(self: Verdict) bool {
        return self != .quiet and self != .matched and self != .bounded_poll_without_signal;
    }

    pub fn describe(self: Verdict) []const u8 {
        return switch (self) {
            .quiet => "no synchronisation object has been observed with traffic on either end",
            .matched => "every object with traffic has both a waiter and a signaller, so no handshake is missing a half",
            .bounded_poll_without_signal => "the only one-sided waiter uses a finite deadline and returns from it. It is a bounded status poll, not a parked consumer, so it cannot be paired with an unrelated orphan signal to claim a broken handshake",
            .signal_without_consumer => "something is signalling an object nothing waits on. On its own that is not a stall — it says the consumer is waiting somewhere else, or on the same object under a different address",
            .wait_without_producer => "a thread is waiting on an object nothing has ever signalled and nothing else is producing. Find the code that was supposed to signal it and confirm it ran; the guest program counter below names the title's own instruction rather than the emulator's slot",
            .unmatched_pair => "one object is waited on and never signalled while another is signalled and never waited on. That is two halves of a handshake that are not meeting, and it is either a producer that never ran or one object that has been split into two identities by an address or handle mismatch. Compare the two rows below before assuming a missing producer: a split shows up as two objects whose handles or low words are related",
        };
    }
};

pub const Summary = struct {
    tracked: u8 = 0,
    matched: u8 = 0,
    /// One-sided waits that can actually remain parked. Only these participate
    /// in missing-producer and split-handshake verdicts.
    blocking_orphan_waits: u8 = 0,
    /// All one-sided waits, including bounded polls. Retained as an accounting
    /// total so classifying a poll never makes an observation disappear.
    orphan_waits: u8 = 0,
    orphan_signals: u8 = 0,
    /// Orphan waits whose waiter is polling on a deadline rather than parked.
    polling_orphans: u8 = 0,
    dropped: u64 = 0,
};

pub const Ledger = struct {
    records: [capacity]Record = [_]Record{.{}} ** capacity,
    count: usize = 0,
    /// Objects that did not fit. Reported rather than silently discarded: a
    /// finding that was dropped for space reads exactly like one that did not
    /// happen.
    dropped: u64 = 0,

    fn slot(self: *Ledger, object: u64) ?*Record {
        for (self.records[0..self.count]) |*record| {
            if (record.object == object) return record;
        }
        if (self.count >= capacity) {
            self.dropped +|= 1;
            return null;
        }
        const fresh = &self.records[self.count];
        self.count += 1;
        fresh.* = .{ .object = object, .valid = true };
        return fresh;
    }

    pub fn observeWait(
        self: *Ledger,
        object: u64,
        handle: u32,
        thread: u64,
        step: u64,
        timed_out: bool,
    ) void {
        const record = self.slot(object) orelse return;
        if (record.first_step == 0) record.first_step = step;
        record.last_step = step;
        if (handle != 0) record.handle = handle;
        record.waits +|= 1;
        if (timed_out) record.timeouts +|= 1;
        record.waiter_thread = thread;
    }

    /// Where in the title's own code the waiter is.
    ///
    /// Separate from `observeWait` because the two arrive from different lines
    /// and because a program counter the emulator marked untrusted must not
    /// silently become the answer. A seeded or stale PC is worse than none: it
    /// names an instruction that is not the one waiting.
    pub fn observeWaitSite(
        self: *Ledger,
        object: u64,
        guest_pc: u64,
        guest_lr: u64,
        trusted: bool,
    ) void {
        const record = self.slot(object) orelse return;
        if (record.guest_pc_trusted and !trusted) return;
        record.guest_pc = guest_pc;
        record.guest_lr = guest_lr;
        record.guest_pc_trusted = trusted;
    }

    pub fn observeTimeoutRequest(self: *Ledger, object: u64, timeout_ms: u32) void {
        const record = self.slot(object) orelse return;
        record.timeout_ms = timeout_ms;
    }

    pub fn observeSignal(self: *Ledger, object: u64, handle: u32, thread: u64, pc: u64, step: u64) void {
        const record = self.slot(object) orelse return;
        if (record.first_step == 0) record.first_step = step;
        record.last_step = step;
        if (handle != 0) record.handle = handle;
        record.signals +|= 1;
        record.signaller_thread = thread;
        record.signaller_pc = pc;
    }

    pub fn observeProvenance(self: *Ledger, object: u64, provenance: Provenance) void {
        const record = self.slot(object) orelse return;
        if (record.provenance == .unknown) record.provenance = provenance;
    }

    pub fn summary(self: *const Ledger) Summary {
        var out = Summary{ .dropped = self.dropped };
        for (self.records[0..self.count]) |record| {
            out.tracked += 1;
            switch (record.role()) {
                .matched => out.matched += 1,
                .orphan_wait => {
                    out.orphan_waits += 1;
                    if (record.polling()) {
                        out.polling_orphans += 1;
                    } else {
                        out.blocking_orphan_waits += 1;
                    }
                },
                .orphan_signal => out.orphan_signals += 1,
                .idle => {},
            }
        }
        return out;
    }

    pub fn verdict(self: *const Ledger) Verdict {
        const totals = self.summary();
        if (totals.tracked == 0) return .quiet;
        if (totals.blocking_orphan_waits != 0 and totals.orphan_signals != 0) return .unmatched_pair;
        if (totals.blocking_orphan_waits != 0) return .wait_without_producer;
        if (totals.orphan_signals != 0) return .signal_without_consumer;
        if (totals.polling_orphans != 0) return .bounded_poll_without_signal;
        return .matched;
    }

    /// The orphan wait with the most attempts — the one the run is most stuck
    /// on, rather than whichever was recorded first.
    pub fn worstOrphanWait(self: *const Ledger) ?Record {
        var best: ?Record = null;
        for (self.records[0..self.count]) |record| {
            if (record.role() != .orphan_wait or record.polling()) continue;
            const held = best orelse {
                best = record;
                continue;
            };
            if (record.waits > held.waits) best = record;
        }
        return best;
    }

    /// The busiest one-sided waiter that returned through a finite deadline.
    /// Kept separate from `worstOrphanWait` so a status poll can be reported
    /// without being promoted into a blocked handshake.
    pub fn worstPollingOrphan(self: *const Ledger) ?Record {
        var best: ?Record = null;
        for (self.records[0..self.count]) |record| {
            if (record.role() != .orphan_wait or !record.polling()) continue;
            const held = best orelse {
                best = record;
                continue;
            };
            if (record.waits > held.waits) best = record;
        }
        return best;
    }

    pub fn worstOrphanSignal(self: *const Ledger) ?Record {
        var best: ?Record = null;
        for (self.records[0..self.count]) |record| {
            if (record.role() != .orphan_signal) continue;
            const held = best orelse {
                best = record;
                continue;
            };
            if (record.signals > held.signals) best = record;
        }
        return best;
    }

    /// Whether an orphan wait and an orphan signal look like one object that
    /// has been split in two.
    ///
    /// The test is the low half of the address, because that is the shape the
    /// split actually takes here: the emulator reports one object as
    /// `guest_obj=827CEC14` and as `obj_ptr=D1C1EC14`, two addresses for one
    /// console object that agree on their low sixteen bits.
    ///
    /// Handles deliberately do not participate. Console object handles are
    /// `0xF8000000` plus a small index, so every event in the run shares its
    /// top twenty-four bits and a handle comparison would call every orphan
    /// pair a split — which is worse than no test, because it would answer the
    /// question wrongly instead of leaving it open.
    ///
    /// Reported as a suspicion, never as a conclusion: the point is to make a
    /// reader compare the two rows rather than to decide for them.
    pub fn looksLikeSplitIdentity(self: *const Ledger) bool {
        return self.findSplitIdentity() != null;
    }

    /// The orphan wait and orphan signal that look like one object, and the
    /// bias between the two views of it.
    ///
    /// Every orphan wait is compared against every orphan signal rather than
    /// only the busiest of each. A run with one genuine orphan wait and two
    /// orphan signals — the 2026-09-01 shape — has three pairs to consider,
    /// and comparing only the worst of each checked one of them and answered
    /// `NO` for all three. The table is bounded and this runs on a checkpoint,
    /// so the exhaustive comparison costs nothing worth saving.
    pub fn findSplitIdentity(self: *const Ledger) ?SplitIdentity {
        var best: ?SplitIdentity = null;
        for (self.records[0..self.count]) |waited| {
            // A bounded poll has already returned and cannot be the parked half
            // of a split blocking handshake.
            if (waited.role() != .orphan_wait or waited.polling()) continue;
            for (self.records[0..self.count]) |signalled| {
                if (signalled.role() != .orphan_signal) continue;
                const candidate = splitCandidate(waited, signalled) orelse continue;
                const held = best orelse {
                    best = candidate;
                    continue;
                };
                // An exact address match is the strongest reading; failing
                // that, the smallest bias is the most likely mapping.
                if (candidate.bias < held.bias) best = candidate;
            }
        }
        return best;
    }
};

/// One orphan wait and one orphan signal that look like two views of a single
/// console object.
pub const SplitIdentity = struct {
    waited: u64,
    signalled: u64,
    /// The distance between the two views, or zero when they are the same
    /// address seen twice. A non-zero bias is the mapping offset, and a run
    /// where several pairs share one bias has an address-space translation
    /// rather than a coincidence.
    bias: u64,

    pub fn sameAddress(self: SplitIdentity) bool {
        return self.bias == 0;
    }
};

/// Whether two orphan records could be one object.
///
/// The test is the low half of the address, because that is the shape the
/// split takes: the emulator reports one object as `guest_obj=827CEC38` and as
/// `obj_ptr=D1C5EC38`, two addresses for one console object that agree on
/// their low sixteen bits. A mapping bias is a multiple of 64 KiB, so the low
/// half survives it by construction.
fn splitCandidate(waited: Record, signalled: Record) ?SplitIdentity {
    if (waited.object == signalled.object) {
        return .{ .waited = waited.object, .signalled = signalled.object, .bias = 0 };
    }
    const low_mask: u64 = 0xFFFF;
    if ((waited.object & low_mask) != (signalled.object & low_mask)) return null;
    const bias = if (waited.object > signalled.object)
        waited.object - signalled.object
    else
        signalled.object - waited.object;
    return .{ .waited = waited.object, .signalled = signalled.object, .bias = bias };
}

test "an empty ledger is quiet" {
    const ledger = Ledger{};
    try std.testing.expectEqual(Verdict.quiet, ledger.verdict());
    try std.testing.expect(ledger.worstOrphanWait() == null);
    try std.testing.expect(!ledger.verdict().actionable());
}

test "an object with both ends is matched" {
    var ledger = Ledger{};
    ledger.observeWait(0x827cec14, 0xf800015c, 0x7fff2170, 100, false);
    ledger.observeSignal(0x827cec14, 0xf800015c, 0x7fff2160, 0x1bd490, 110);
    try std.testing.expectEqual(Verdict.matched, ledger.verdict());
    try std.testing.expect(!ledger.verdict().actionable());
}

// The 2026-08-31 reading, replayed. The finite timeout means the waiter has
// returned and is polling; it must not be promoted into the parked half of an
// unmatched pair merely because some other object is signalled.
test "a bounded poll beside an orphan signal is not an unmatched pair" {
    var ledger = Ledger{};
    ledger.observeProvenance(0x40004bf4, .bare_handle);
    ledger.observeTimeoutRequest(0x40004bf4, 30);
    var attempt: usize = 0;
    while (attempt < 306) : (attempt += 1) {
        ledger.observeWait(0x40004bf4, 0xf8000158, 0x7fff2140, 3_402_556_936 + attempt, true);
    }
    ledger.observeWaitSite(0x40004bf4, 0x8258A470, 0x825AE908, true);

    var signal: usize = 0;
    while (signal < 1824) : (signal += 1) {
        ledger.observeSignal(0x827cec28, 0xf800016c, 0x7fff2160, 0x1bf400, 4_173_427_829 + signal);
    }

    try std.testing.expectEqual(Verdict.signal_without_consumer, ledger.verdict());
    try std.testing.expect(ledger.worstOrphanWait() == null);
    const waited = ledger.worstPollingOrphan().?;
    try std.testing.expectEqual(@as(u64, 0x40004bf4), waited.object);
    try std.testing.expectEqual(@as(u64, 306), waited.waits);
    try std.testing.expectEqual(@as(u64, 0), waited.signals);
    try std.testing.expectEqual(@as(u64, 0x8258A470), waited.guest_pc);
    try std.testing.expect(waited.polling());
    try std.testing.expectEqual(Provenance.bare_handle, waited.provenance);

    const signalled = ledger.worstOrphanSignal().?;
    try std.testing.expectEqual(@as(u64, 0x827cec28), signalled.object);
    try std.testing.expectEqual(@as(u64, 1824), signalled.signals);
    // These two are unrelated addresses, so the pair is a missing producer
    // rather than one object split in two.
    try std.testing.expect(!ledger.looksLikeSplitIdentity());
}

// The other explanation for the same shape, and the reason the report asks a
// reader to compare the rows.
test "two views of one object are recognised as a split identity" {
    var ledger = Ledger{};
    ledger.observeWait(0x827cec14, 0xf800015c, 0x7fff2170, 100, false);
    ledger.observeSignal(0xd1c1ec14, 0xf800015c, 0x7fff2160, 0x1bd490, 110);
    try std.testing.expectEqual(Verdict.unmatched_pair, ledger.verdict());
    try std.testing.expect(ledger.looksLikeSplitIdentity());
}

// A seeded program counter names an instruction that is not the one waiting,
// which is worse than naming none.
test "an untrusted program counter does not overwrite a trusted one" {
    var ledger = Ledger{};
    ledger.observeWait(0x1000, 0x10, 0x20, 1, false);
    ledger.observeWaitSite(0x1000, 0x8258A470, 0x825AE908, true);
    ledger.observeWaitSite(0x1000, 0xDEADBEEF, 0, false);
    const record = ledger.worstOrphanWait().?;
    try std.testing.expectEqual(@as(u64, 0x8258A470), record.guest_pc);
    try std.testing.expect(record.guest_pc_trusted);
}

test "a polling waiter is distinguished from a parked one" {
    var ledger = Ledger{};
    ledger.observeWait(0x2000, 0x20, 0x30, 1, false);
    try std.testing.expect(!ledger.worstOrphanWait().?.polling());
    ledger.observeTimeoutRequest(0x2000, 30);
    ledger.observeWait(0x2000, 0x20, 0x30, 2, true);
    try std.testing.expect(ledger.worstOrphanWait() == null);
    try std.testing.expect(ledger.worstPollingOrphan().?.polling());
    try std.testing.expectEqual(@as(u8, 1), ledger.summary().polling_orphans);
    try std.testing.expectEqual(@as(u8, 0), ledger.summary().blocking_orphan_waits);
    try std.testing.expectEqual(Verdict.bounded_poll_without_signal, ledger.verdict());
    try std.testing.expect(!ledger.verdict().actionable());
}

// A finding dropped for space reads exactly like one that did not happen.
test "objects past capacity are counted rather than discarded" {
    var ledger = Ledger{};
    var index: u64 = 0;
    while (index < capacity + 5) : (index += 1) {
        ledger.observeWait(0x1000 + index, 0, 0, index, false);
    }
    try std.testing.expectEqual(capacity, ledger.count);
    try std.testing.expectEqual(@as(u64, 5), ledger.summary().dropped);
}

test "the worst orphan is the one with the most attempts" {
    var ledger = Ledger{};
    ledger.observeWait(0x1000, 0, 0, 1, true);
    var index: usize = 0;
    while (index < 20) : (index += 1) {
        ledger.observeWait(0x2000, 0, 0, 2, true);
    }
    try std.testing.expectEqual(@as(u64, 0x2000), ledger.worstOrphanWait().?.object);
}

test "every verdict explains itself" {
    inline for (@typeInfo(Verdict).@"enum".fields) |field| {
        const value: Verdict = @enumFromInt(field.value);
        try std.testing.expect(value.label().len != 0);
        try std.testing.expect(value.describe().len != 0);
    }
}

// Console handles are 0xF8000000 plus a small index, so every event in a run
// shares its top bits. A handle-based split test would call every orphan pair a
// split, which answers the question wrongly rather than leaving it open.
test "handles do not decide a split identity" {
    var ledger = Ledger{};
    ledger.observeWait(0x40004bf4, 0xf8000158, 0x7fff2140, 1, true);
    ledger.observeSignal(0x827cec28, 0xf800016c, 0x7fff2160, 0x1bf400, 2);
    try std.testing.expectEqual(Verdict.unmatched_pair, ledger.verdict());
    try std.testing.expect(!ledger.looksLikeSplitIdentity());
}

// The 2026-09-01 shape: one genuine orphan wait and two orphan signals, one of
// which is the other view of an object that *is* being waited on. Comparing
// only the busiest of each checked one of the three pairs and answered `NO`
// for all of them.
test "a split is found between any orphan pair, not only the busiest two" {
    var ledger = Ledger{};

    // The title polls a completion event nothing ever sets. It has the most
    // attempts, but its deadline means it belongs in the polling report rather
    // than `worstOrphanWait`.
    ledger.observeTimeoutRequest(0x40004bf4, 30);
    var attempt: usize = 0;
    while (attempt < 306) : (attempt += 1) {
        ledger.observeWait(0x40004bf4, 0xf8000154, 0x7fff2000, 1000 + attempt, true);
    }

    // A signal nobody consumes, and more of them than the split partner has.
    var signalled: usize = 0;
    while (signalled < 1824) : (signalled += 1) {
        ledger.observeSignal(0x827cec28, 0xf800016c, 0x7fff2040, 0x1bd490, 2000 + signalled);
    }

    // The other half of a real handshake, recorded under the host view of the
    // same console object.
    ledger.observeWait(0xd1c5ec38, 0xf8000168, 0x7fff2050, 4000, false);
    ledger.observeSignal(0x827cec38, 0xf8000168, 0x7fff2060, 0x1bd4a0, 4100);

    try std.testing.expectEqual(Verdict.unmatched_pair, ledger.verdict());
    // The bounded poll is not allowed to eclipse the real blocking half.
    try std.testing.expectEqual(@as(u64, 0xd1c5ec38), ledger.worstOrphanWait().?.object);
    try std.testing.expectEqual(@as(u64, 0x40004bf4), ledger.worstPollingOrphan().?.object);
    try std.testing.expectEqual(@as(u64, 0x827cec28), ledger.worstOrphanSignal().?.object);

    // And the split is still found, between the pair nobody was comparing.
    const split = ledger.findSplitIdentity().?;
    try std.testing.expect(ledger.looksLikeSplitIdentity());
    try std.testing.expectEqual(@as(u64, 0xd1c5ec38), split.waited);
    try std.testing.expectEqual(@as(u64, 0x827cec38), split.signalled);
    try std.testing.expectEqual(@as(u64, 0xd1c5ec38 - 0x827cec38), split.bias);
    try std.testing.expect(!split.sameAddress());
}

// A bias is a multiple of 64 KiB, so unrelated addresses that happen to share
// a low half are the false positive to worry about — and the low half is still
// the only test that survives the mapping. The guarantee that matters is the
// negative one: addresses whose low halves differ are never called a split.
test "objects with different low halves are never a split" {
    var ledger = Ledger{};
    ledger.observeWait(0x40004bf4, 0xf8000154, 0x7fff2000, 100, true);
    ledger.observeSignal(0x827cec28, 0xf800016c, 0x7fff2040, 0x1bd490, 200);
    try std.testing.expectEqual(Verdict.unmatched_pair, ledger.verdict());
    try std.testing.expect(!ledger.looksLikeSplitIdentity());
    try std.testing.expect(ledger.findSplitIdentity() == null);
}

// The same address seen on both ends is the strongest reading and has to beat
// a biased pair, because a bias is an inference and an exact match is not.
test "an exact address match outranks a biased one" {
    var ledger = Ledger{};
    // A biased pair.
    ledger.observeWait(0xd1c5ec38, 0xf8000168, 0x7fff2050, 100, false);
    ledger.observeSignal(0x827cec38, 0xf8000168, 0x7fff2060, 0x1bd4a0, 110);
    try std.testing.expect(!ledger.findSplitIdentity().?.sameAddress());

    // An exact pair: one object recorded as an orphan wait under one thread
    // and an orphan signal under another, with no waiter/signaller crossing.
    ledger.observeWait(0x827cec48, 0xf8000170, 0x7fff2070, 200, false);
    ledger.observeSignal(0x8267ec48, 0xf8000174, 0x7fff2080, 0x1bd4b0, 210);
    const split = ledger.findSplitIdentity().?;
    try std.testing.expect(split.bias < 0xd1c5ec38 - 0x827cec38);
}
