//! Whether the guest's waits are waits, or a spin wearing a wait's name.
//!
//! `KeWaitForSingleObject` returning `0` means the object was signalled. It
//! does not mean the caller *waited*: an event that is already set satisfies the
//! wait without the thread ever blocking. Both outcomes return the same status,
//! so a log full of `result=00000000` is equally consistent with a healthy
//! producer/consumer handshake and with a loop that never blocks, never
//! consumes a signal, and never makes progress.
//!
//! Those are opposite failures. A handshake where every wait blocks and is
//! released is the system working. A handshake where every wait is satisfied on
//! arrival is a spin: the consumer runs continuously, the producer is never
//! given the CPU it needs, and the whole pair free-runs at whatever rate the
//! scheduler happens to allow. From the outside the second one looks like a
//! GPU stall, an I/O stall, or a livelock, depending on which thread you
//! happened to sample.
//!
//! ## What separates them
//!
//! The ratio, and only the ratio. One wait that returns immediately is normal —
//! the producer got there first. A run where essentially *all* of them do has a
//! signal nobody is consuming, because a consumed signal leaves the event clear
//! and the next wait blocks. So this counts both outcomes per object and
//! reports the proportion, and it refuses to draw a conclusion from a sample
//! too small to have one.
//!
//! ## Why per-object and not per-run
//!
//! A run has many handshakes. An audio pump that legitimately runs hot and a
//! render loop that is wedged produce one indistinguishable aggregate, and the
//! aggregate is dominated by whichever runs faster — which is always the
//! healthy one. Per-object, the wedged pair stands out precisely because it is
//! the one whose waits never block.

const std = @import("std");

/// Wait status values a caller can distinguish. Named because `0x102` in a log
/// is a number nobody remembers.
pub const WaitStatus = enum {
    /// The object was signalled. Says nothing about whether the caller blocked.
    signalled,
    /// The wait ran out of time. Proof the caller really did block, and that
    /// the signal did not come.
    timed_out,
    /// An alert or APC interrupted the wait.
    alerted,
    other,

    pub fn fromCode(code: u32) WaitStatus {
        return switch (code) {
            0x0000_0000 => .signalled,
            0x0000_0101 => .alerted,
            0x0000_0102 => .timed_out,
            else => .other,
        };
    }

    pub fn label(self: WaitStatus) []const u8 {
        return switch (self) {
            .signalled => "signalled",
            .timed_out => "timed_out",
            .alerted => "alerted",
            .other => "other",
        };
    }
};

/// The minimum number of waits on one object before a ratio means anything.
/// Below this, "every wait returned immediately" is three samples and a guess.
pub const minimum_sample: u64 = 64;

/// Proportion of immediate satisfactions above which a handshake is called a
/// spin. Not 100%: a real spin still occasionally blocks when the scheduler
/// interleaves differently, and demanding perfection would let a 99% spin
/// report as healthy.
pub const spin_ratio_percent: u64 = 95;

pub const Verdict = enum {
    /// Too few waits to say anything.
    insufficient_sample,
    /// Waits block and are released. The handshake is doing its job.
    consuming_signals,
    /// Essentially every wait is satisfied on arrival. The waiter never blocks,
    /// so nothing is being consumed and the pair free-runs.
    never_blocks,
    /// Waits block and time out. The signal is not arriving at all.
    signal_never_arrives,

    pub fn label(self: Verdict) []const u8 {
        return switch (self) {
            .insufficient_sample => "insufficient_sample",
            .consuming_signals => "consuming_signals",
            .never_blocks => "NEVER_BLOCKS",
            .signal_never_arrives => "SIGNAL_NEVER_ARRIVES",
        };
    }

    pub fn meaning(self: Verdict) []const u8 {
        return switch (self) {
            .insufficient_sample => "too few waits on this object to distinguish a handshake from a spin",
            .consuming_signals => "waits block and are released, so signals are being produced and consumed and this handshake is working",
            .never_blocks => "essentially every wait was satisfied the moment it was made. The waiter never blocks, so it never consumes a signal and never yields — the pair free-runs and makes progress only at whatever rate the scheduler allows. From outside this looks like a stall in whatever subsystem the loop belongs to, and it is not one",
            .signal_never_arrives => "waits block and time out. The waiter is correct and the producer is not producing; look at the thread that should be signalling",
        };
    }

    /// Whether this verdict describes something wrong.
    pub fn healthy(self: Verdict) bool {
        return self == .consuming_signals or self == .insufficient_sample;
    }
};

pub const Object = struct {
    handle: u32 = 0,
    waits: u64 = 0,
    signalled: u64 = 0,
    timed_out: u64 = 0,
    alerted: u64 = 0,
    /// `KeSetEvent` calls that found the event already set. On its own this is a
    /// literal in some emulator builds and proves nothing, which is why the
    /// verdict is built from wait outcomes instead — but a high count alongside
    /// `never_blocks` corroborates it.
    sets_already_signalled: u64 = 0,
    sets: u64 = 0,

    pub fn immediateRatioPercent(self: Object) u64 {
        if (self.waits == 0) return 0;
        return self.signalled * 100 / self.waits;
    }

    pub fn verdict(self: Object) Verdict {
        if (self.waits < minimum_sample) return .insufficient_sample;
        if (self.timed_out * 100 / self.waits >= spin_ratio_percent) return .signal_never_arrives;
        if (self.immediateRatioPercent() >= spin_ratio_percent) return .never_blocks;
        return .consuming_signals;
    }
};

pub const max_objects = 24;

pub const Ledger = struct {
    objects: [max_objects]Object = [_]Object{.{}} ** max_objects,
    count: usize = 0,
    /// Waits on objects past the table's capacity. Counted rather than dropped:
    /// a table that silently stops recording implies the traffic stopped.
    untracked_waits: u64 = 0,
    /// Waits observed with no handle attached. The emulator logs the result of
    /// a wait and the handle of a set on different lines, so a result that
    /// arrives before any handle is known cannot be attributed.
    unattributed_waits: u64 = 0,
    total_waits: u64 = 0,
    total_signalled: u64 = 0,
    total_timed_out: u64 = 0,

    fn slot(self: *Ledger, handle: u32) ?*Object {
        for (self.objects[0..self.count]) |*object| {
            if (object.handle == handle) return object;
        }
        if (self.count == max_objects) return null;
        const object = &self.objects[self.count];
        object.* = .{ .handle = handle };
        self.count += 1;
        return object;
    }

    pub fn observeWait(self: *Ledger, handle: u32, status: WaitStatus) void {
        self.total_waits +|= 1;
        switch (status) {
            .signalled => self.total_signalled +|= 1,
            .timed_out => self.total_timed_out +|= 1,
            else => {},
        }
        if (handle == 0) {
            self.unattributed_waits +|= 1;
            return;
        }
        const object = self.slot(handle) orelse {
            self.untracked_waits +|= 1;
            return;
        };
        object.waits +|= 1;
        switch (status) {
            .signalled => object.signalled +|= 1,
            .timed_out => object.timed_out +|= 1,
            .alerted => object.alerted +|= 1,
            .other => {},
        }
    }

    pub fn observeSet(self: *Ledger, handle: u32, already_signalled: bool) void {
        if (handle == 0) return;
        const object = self.slot(handle) orelse return;
        object.sets +|= 1;
        if (already_signalled) object.sets_already_signalled +|= 1;
    }

    /// The object whose handshake is most clearly broken, if any. Ordered by
    /// how much traffic it carries, because a wedged loop running millions of
    /// times is a bigger finding than one that ran a hundred.
    pub fn worst(self: *const Ledger) ?Object {
        var chosen: ?Object = null;
        for (self.objects[0..self.count]) |object| {
            if (object.verdict().healthy()) continue;
            if (chosen == null or object.waits > chosen.?.waits) chosen = object;
        }
        return chosen;
    }

    /// The same judgement over the run's totals rather than one object.
    ///
    /// Needed because the emulator logs a wait's *result* and an event's
    /// *handle* on separate lines, so most waits arrive unattributed. An
    /// aggregate can be dominated by whichever handshake runs hottest — which
    /// is always a healthy one — so this is deliberately reported as weaker
    /// evidence than a per-object verdict, and never instead of one.
    pub fn aggregateVerdict(self: *const Ledger) Verdict {
        if (self.total_waits < minimum_sample) return .insufficient_sample;
        if (self.total_timed_out * 100 / self.total_waits >= spin_ratio_percent) return .signal_never_arrives;
        if (self.total_signalled * 100 / self.total_waits >= spin_ratio_percent) return .never_blocks;
        return .consuming_signals;
    }

    pub fn aggregateImmediatePercent(self: *const Ledger) u64 {
        if (self.total_waits == 0) return 0;
        return self.total_signalled * 100 / self.total_waits;
    }

    pub fn verdict(self: *const Ledger) []const u8 {
        if (self.total_waits == 0)
            return "no guest wait has been observed, so nothing can be said about whether waits consume signals";
        if (self.worst()) |object| return object.verdict().meaning();
        if (self.count == 0)
            return "waits were observed and none could be attributed to an object, because the emulator logs a wait's result and an event's handle on separate lines. The aggregate ratio below is the only ratio available, and an aggregate is dominated by whichever handshake runs hottest — so read it as weak evidence. Logging the object handle alongside the wait result would make this a per-object answer";
        return "every object with enough samples blocks and is released, so the guest's waits are consuming the signals they wait on";
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "a wait status is named rather than left as a number" {
    try std.testing.expectEqual(WaitStatus.signalled, WaitStatus.fromCode(0));
    try std.testing.expectEqual(WaitStatus.timed_out, WaitStatus.fromCode(0x102));
    try std.testing.expectEqual(WaitStatus.alerted, WaitStatus.fromCode(0x101));
    try std.testing.expectEqual(WaitStatus.other, WaitStatus.fromCode(0xC0000001));
}

// The failure the module exists for. Every wait returns the same status a
// healthy handshake returns, and the ratio is the only thing that separates
// them.
test "a handshake whose waits never block is named as a spin" {
    var ledger = Ledger{};
    var index: u64 = 0;
    while (index < 1000) : (index += 1) ledger.observeWait(0xF8000168, .signalled);

    const object = ledger.objects[0];
    try std.testing.expectEqual(Verdict.never_blocks, object.verdict());
    try std.testing.expectEqual(@as(u64, 100), object.immediateRatioPercent());
    try std.testing.expect(!object.verdict().healthy());
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "free-runs") != null);
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "it is not one") != null);
}

test "a handshake that blocks and is released is healthy" {
    var ledger = Ledger{};
    var index: u64 = 0;
    while (index < 100) : (index += 1) {
        ledger.observeWait(0xF800016C, if (index % 2 == 0) .signalled else .timed_out);
    }
    try std.testing.expectEqual(Verdict.consuming_signals, ledger.objects[0].verdict());
    try std.testing.expect(ledger.worst() == null);
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "consuming the signals") != null);
}

test "a waiter that blocks and times out points at the producer, not the waiter" {
    var ledger = Ledger{};
    var index: u64 = 0;
    while (index < 200) : (index += 1) ledger.observeWait(0xF8000200, .timed_out);
    try std.testing.expectEqual(Verdict.signal_never_arrives, ledger.objects[0].verdict());
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "thread that should be signalling") != null);
}

// Three samples that all returned immediately is not evidence of anything.
test "a sample too small to have a ratio refuses to draw a conclusion" {
    var ledger = Ledger{};
    ledger.observeWait(0xF8000168, .signalled);
    ledger.observeWait(0xF8000168, .signalled);
    ledger.observeWait(0xF8000168, .signalled);
    try std.testing.expectEqual(Verdict.insufficient_sample, ledger.objects[0].verdict());
    try std.testing.expect(ledger.objects[0].verdict().healthy());
    try std.testing.expect(ledger.worst() == null);
}

// A hot healthy pump and a wedged loop produce one aggregate dominated by the
// healthy one, which is why the ledger is per-object.
test "a busy healthy object does not mask a wedged one" {
    var ledger = Ledger{};
    var index: u64 = 0;
    while (index < 100_000) : (index += 1) {
        ledger.observeWait(0xF8000100, if (index % 2 == 0) .signalled else .timed_out);
    }
    while (index < 100_500) : (index += 1) ledger.observeWait(0xF8000200, .signalled);

    // The aggregate looks fine.
    try std.testing.expect(ledger.total_signalled > ledger.total_timed_out);
    // The wedged object is still found and named.
    const worst = ledger.worst().?;
    try std.testing.expectEqual(@as(u32, 0xF8000200), worst.handle);
    try std.testing.expectEqual(Verdict.never_blocks, worst.verdict());
}

// Between two broken objects, the one carrying the traffic is the finding.
test "the worst object is the broken one with the most traffic" {
    var ledger = Ledger{};
    var index: u64 = 0;
    while (index < 100) : (index += 1) ledger.observeWait(0xAAAA, .signalled);
    while (index < 1100) : (index += 1) ledger.observeWait(0xBBBB, .signalled);
    try std.testing.expectEqual(@as(u32, 0xBBBB), ledger.worst().?.handle);
}

test "waits with no handle and waits past capacity are counted rather than dropped" {
    var ledger = Ledger{};
    ledger.observeWait(0, .signalled);
    try std.testing.expectEqual(@as(u64, 1), ledger.unattributed_waits);
    try std.testing.expectEqual(@as(usize, 0), ledger.count);

    var handle: u32 = 1;
    while (handle <= max_objects) : (handle += 1) ledger.observeWait(handle, .signalled);
    try std.testing.expectEqual(@as(usize, max_objects), ledger.count);

    ledger.observeWait(0xDEAD, .signalled);
    try std.testing.expectEqual(@as(u64, 1), ledger.untracked_waits);
    try std.testing.expectEqual(@as(usize, max_objects), ledger.count);
}

// The set-side counter corroborates and never decides: in some emulator builds
// the field it comes from is a literal.
test "set observations are recorded without being allowed to decide the verdict" {
    var ledger = Ledger{};
    var index: u64 = 0;
    while (index < 100) : (index += 1) {
        ledger.observeWait(0xF8000168, if (index % 2 == 0) .signalled else .timed_out);
        ledger.observeSet(0xF8000168, true);
    }
    try std.testing.expectEqual(@as(u64, 100), ledger.objects[0].sets_already_signalled);
    // Every set found the event already signalled and the waits still block, so
    // the handshake is healthy and the set counter did not override that.
    try std.testing.expectEqual(Verdict.consuming_signals, ledger.objects[0].verdict());
}

// The emulator's wait log omits the handle, so most runs have only this.
test "the aggregate verdict works when nothing could be attributed" {
    var ledger = Ledger{};
    var index: u64 = 0;
    // The observed run: 4232 immediate, 333 timeouts, no handles.
    while (index < 4232) : (index += 1) ledger.observeWait(0, .signalled);
    while (index < 4565) : (index += 1) ledger.observeWait(0, .timed_out);

    try std.testing.expectEqual(@as(usize, 0), ledger.count);
    try std.testing.expectEqual(@as(u64, 4565), ledger.unattributed_waits);
    try std.testing.expectEqual(@as(u64, 92), ledger.aggregateImmediatePercent());
    // Just under the spin threshold: a third of a thousand waits really did
    // block, so calling the whole run a spin would be wrong.
    try std.testing.expectEqual(Verdict.consuming_signals, ledger.aggregateVerdict());
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "separate lines") != null);
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "weak evidence") != null);
}

test "an empty ledger says nothing rather than reporting health" {
    const ledger = Ledger{};
    try std.testing.expect(std.mem.indexOf(u8, ledger.verdict(), "no guest wait has been observed") != null);
}
