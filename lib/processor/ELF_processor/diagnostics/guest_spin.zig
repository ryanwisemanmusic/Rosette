//! Guest spin forensics: a thread that keeps spinning at PAUSE while the
//! title presents nothing is waiting for something. This names what.
//!
//! 2026-10-02: three runs froze at Halo 3's main menu with MAIN_THREAD and
//! RENDER both spinning in one Xenia-compiled function. It counts down four
//! turns of eight PAUSEs, then polls bit 0x02 of a byte at r29+0x2ABD. The
//! translated loop retires exactly the interpreter's state, so it was waiting
//! correctly; nothing in the log said for whom. The report this module drives
//! says it in three parts:
//!
//!  - the spinner's PowerPC registers and guest call stack, and every other
//!    guest thread's JIT frames with the PowerPC return address each call
//!    stored, so a wait cycle can be read off the threads' stacks;
//!  - the guest memory the spinner actually polls, captured by interpreting
//!    a few hundred of its steps with a read capture (translated loads never
//!    pass the interpreter's read path);
//!  - every later write to those bytes, by any thread, by any path: watched
//!    pages are withheld from the write TLB, so translated stores take the
//!    helper, and bulk copies are checked at their one exit.

const std = @import("std");

/// How long the frame count must stand still with this thread spinning.
pub const stall_ns: u64 = 6 * std.time.ns_per_s;
/// And how many PAUSEs it must have reached since the count last moved.
pub const min_pauses: u64 = 1 << 16;
/// The clock is read only on every this-many PAUSEs: a spinner reaches one
/// every few hundred nanoseconds.
pub const clock_stride: u64 = 256;
/// Steps the spinner is interpreted for while its reads are captured: Xenia's
/// wait loops are a few dozen instructions, so several turns.
pub const capture_steps: u32 = 512;
pub const capture_capacity: usize = 64;
/// Bound the detailed captures within one stalled frame. A new frame starts
/// a new episode, so an earlier loading-screen pause cannot consume the
/// budget needed to diagnose a later permanent stall.
pub const reports_per_thread: u8 = 3;
pub const recapture_interval_ns: u64 = 30 * std.time.ns_per_s;
/// How often a stalled spinner asks for an assist.
pub const assist_interval_ns: u64 = std.time.ns_per_s;

pub const ReadRecord = struct {
    rip: u64 = 0,
    address: u64 = 0,
    size: u8 = 0,
    first: u64 = 0,
    last: u64 = 0,
    count: u32 = 0,
};

/// One guest thread's spin streak and read capture. Only the host thread
/// executing this guest thread writes it.
pub const ThreadSpin = struct {
    /// One progress probe per 1024 code-profile samples (65,536 steps).
    /// This catches a busy render thread that never executes PAUSE.
    progress_probe_stride: u10 = 0,
    seen_swaps: u64 = 0,
    seen_swaps_ns: u64 = 0,
    pauses_since_swap: u64 = 0,
    reports: u8 = 0,
    reported_at_swaps: ?u64 = null,
    /// Watch episode observed when this capture began. A present during the
    /// capture must not let its old reads arm the next episode.
    capture_watch_epoch: u64 = 0,
    capture_remaining: u32 = 0,
    capture_len: u32 = 0,
    capture_overflow: u32 = 0,
    trigger_rip: u64 = 0,
    trigger_ns: u64 = 0,
    capture: [capture_capacity]ReadRecord = [_]ReadRecord{.{}} ** capture_capacity,
    /// When the stall assist last acted for this thread.
    last_assist_ns: u64 = 0,
    assists: u64 = 0,

    fn resetForFrame(self: *ThreadSpin, swaps: u64, now_ns: u64) void {
        self.seen_swaps = swaps;
        self.seen_swaps_ns = now_ns;
        self.pauses_since_swap = 0;
        self.reports = 0;
        self.reported_at_swaps = null;
        self.last_assist_ns = 0;
        self.assists = 0;
    }

    fn armCapture(self: *ThreadSpin, rip: u64, swaps: u64, now_ns: u64) bool {
        if (swaps == 0 or self.reports >= reports_per_thread) return false;
        if (self.reported_at_swaps) |at| {
            if (at == swaps and now_ns -| self.trigger_ns < recapture_interval_ns) return false;
        }
        if (now_ns -| self.seen_swaps_ns < stall_ns) return false;
        self.reports += 1;
        self.reported_at_swaps = swaps;
        self.trigger_rip = rip;
        self.trigger_ns = now_ns;
        self.capture_remaining = capture_steps;
        self.capture_len = 0;
        self.capture_overflow = 0;
        return true;
    }

    /// A running title thread can stall in a tight loop with no PAUSE. The
    /// caller probes it only every 65,536 steps; sharing the frame and report
    /// budget with PAUSE captures prevents duplicate work and keeps the
    /// normal frame path free of time reads.
    pub fn noteProgress(self: *ThreadSpin, rip: u64, swaps: u64, now_ns: u64) bool {
        if (self.capture_remaining != 0) return false;
        if (swaps != self.seen_swaps or self.seen_swaps_ns == 0) {
            self.resetForFrame(swaps, now_ns);
            return false;
        }
        return self.armCapture(rip, swaps, now_ns);
    }

    /// While the frame count stands still past `stall_ns`, an assist is due
    /// once every `assist_interval_ns` per spinning thread.
    pub fn assistDue(self: *ThreadSpin, swaps: u64, now_ns: u64) bool {
        if (swaps == 0 or swaps != self.seen_swaps or self.seen_swaps_ns == 0) return false;
        if (self.pauses_since_swap < min_pauses or now_ns -| self.seen_swaps_ns < stall_ns) return false;
        if (now_ns -| self.last_assist_ns < assist_interval_ns) return false;
        self.last_assist_ns = now_ns;
        self.assists +|= 1;
        return true;
    }

    /// Whether this PAUSE needs the clock: the first after the frame count
    /// moved, and every `clock_stride`th after that.
    pub fn wantsClock(self: *const ThreadSpin, swaps: u64) bool {
        if (self.capture_remaining != 0) return false;
        if (swaps != self.seen_swaps or self.seen_swaps_ns == 0) return true;
        return (self.pauses_since_swap +% 1) % clock_stride == 0;
    }

    /// The parallel executor samples PAUSE telemetry at its existing
    /// 256-hint scheduling boundary. Batch the diagnostic counter so that
    /// the coarse sample preserves the same clock stride and pause threshold.
    pub fn wantsClockBatch(self: *const ThreadSpin, swaps: u64, pause_count: u64) bool {
        if (self.capture_remaining != 0) return false;
        if (swaps != self.seen_swaps or self.seen_swaps_ns == 0) return true;
        return (self.pauses_since_swap +| pause_count) % clock_stride == 0;
    }

    /// Count a PAUSE. With `now_ns` (see `wantsClock`), true when this one
    /// starts a capture: the thread has spun for `stall_ns` and
    /// `min_pauses` while `swaps` stood still.
    pub fn notePause(self: *ThreadSpin, rip: u64, swaps: u64, now_ns: ?u64) bool {
        if (self.capture_remaining != 0) return false;
        if (swaps != self.seen_swaps or self.seen_swaps_ns == 0) {
            self.resetForFrame(swaps, now_ns orelse 1);
            return false;
        }
        self.pauses_since_swap +|= 1;
        const now = now_ns orelse return false;
        if (self.pauses_since_swap < min_pauses) return false;
        return self.armCapture(rip, swaps, now);
    }

    pub fn notePauseBatch(self: *ThreadSpin, rip: u64, swaps: u64, now_ns: ?u64, pause_count: u64) bool {
        if (self.capture_remaining != 0) return false;
        if (swaps != self.seen_swaps or self.seen_swaps_ns == 0) {
            self.resetForFrame(swaps, now_ns orelse 1);
            return false;
        }
        self.pauses_since_swap +|= pause_count;
        const now = now_ns orelse return false;
        if (self.pauses_since_swap < min_pauses) return false;
        return self.armCapture(rip, swaps, now);
    }

    /// One interpreted read while capturing: the first value and the last,
    /// once per address and size.
    pub fn noteRead(self: *ThreadSpin, rip: u64, address: u64, size: u8, value: u64) void {
        for (self.capture[0..self.capture_len]) |*record| {
            if (record.address == address and record.size == size) {
                record.last = value;
                record.count +|= 1;
                return;
            }
        }
        if (self.capture_len == capture_capacity) {
            self.capture_overflow +|= 1;
            return;
        }
        self.capture[self.capture_len] = .{ .rip = rip, .address = address, .size = size, .first = value, .last = value, .count = 1 };
        self.capture_len += 1;
    }
};

/// Process-wide watched guest ranges. Arming is rare and serialised by a
/// spin flag; the check on every guest store is one relaxed load while
/// nothing is armed.
pub const WatchSet = struct {
    pub const capacity = 32;
    /// Every watched address must retain its own writer evidence. A busy
    /// clock word previously exhausted one process-wide budget before a
    /// later stalled frame armed the queue entry we needed to investigate.
    pub const initial_logged_hits: u64 = 8;

    addresses: [capacity]std.atomic.Value(u64) = [_]std.atomic.Value(u64){.init(0)} ** capacity,
    widths: [capacity]std.atomic.Value(u64) = [_]std.atomic.Value(u64){.init(0)} ** capacity,
    hits: [capacity]std.atomic.Value(u64) = [_]std.atomic.Value(u64){.init(0)} ** capacity,
    slot_epochs: [capacity]std.atomic.Value(u64) = [_]std.atomic.Value(u64){.init(0)} ** capacity,
    /// The value each watch held when it was armed, for the summary.
    armed_values: [capacity]std.atomic.Value(u64) = [_]std.atomic.Value(u64){.init(0)} ** capacity,
    count: std.atomic.Value(u32) = .init(0),
    capacity_drops: std.atomic.Value(u32) = .init(0),
    epoch: std.atomic.Value(u64) = .init(1),
    arming: std.atomic.Value(u32) = .init(0),

    pub const Match = struct { index: usize, epoch: u64 };

    pub inline fn armed(self: *const WatchSet) bool {
        return self.count.load(.monotonic) != 0;
    }

    /// The first watch `[address, address + width)` overlaps.
    pub fn overlapping(self: *const WatchSet, address: u64, width: u64) ?usize {
        return if (self.overlappingMatch(address, width)) |match| match.index else null;
    }

    /// Carry the episode identity to the write reporter. A present may retire
    /// and reuse the same slot between the range check and the store report.
    pub fn overlappingMatch(self: *const WatchSet, address: u64, width: u64) ?Match {
        const epoch = self.epoch.load(.acquire);
        const n = @min(self.count.load(.acquire), capacity);
        for (0..n) |index| {
            if (self.slot_epochs[index].load(.acquire) != epoch) continue;
            const start = self.addresses[index].load(.acquire);
            const length = self.widths[index].load(.monotonic);
            if (self.slot_epochs[index].load(.acquire) != epoch) continue;
            if (start == 0 or length == 0) continue;
            if (address < start +| length and address +| @max(width, 1) > start and
                self.epoch.load(.acquire) == epoch) return .{ .index = index, .epoch = epoch };
        }
        return null;
    }

    pub fn pageWatched(self: *const WatchSet, page: u64, page_bytes: u64) bool {
        if (!self.armed()) return false;
        return self.overlapping(page, page_bytes) != null;
    }

    /// Watch `[address, address + width)`: its index, existing or new, or
    /// null when the set is full.
    pub fn arm(self: *WatchSet, address: u64, width: u64, value: u64) ?usize {
        return self.armForEpoch(self.epoch.load(.acquire), address, width, value);
    }

    /// Reject a capture whose frame presented while its interpreted reads
    /// were still being collected. The epoch check happens under the arming
    /// lock, so it cannot revive a retired watch after a present.
    pub fn armForEpoch(self: *WatchSet, expected_epoch: u64, address: u64, width: u64, value: u64) ?usize {
        while (self.arming.cmpxchgWeak(0, 1, .acquire, .monotonic) != null) std.atomic.spinLoopHint();
        defer self.arming.store(0, .release);
        const epoch = self.epoch.load(.monotonic);
        if (epoch != expected_epoch) return null;
        const n = @min(self.count.load(.acquire), capacity);
        for (0..n) |index| {
            if (self.addresses[index].load(.monotonic) == address and self.widths[index].load(.monotonic) == width) return index;
        }
        if (n == capacity) {
            _ = self.capacity_drops.fetchAdd(1, .monotonic);
            return null;
        }
        self.hits[n].store(0, .monotonic);
        self.widths[n].store(width, .monotonic);
        self.armed_values[n].store(value, .monotonic);
        self.addresses[n].store(address, .release);
        self.slot_epochs[n].store(epoch, .release);
        self.count.store(@intCast(n + 1), .release);
        return n;
    }

    /// A present ends the stalled-frame episode. Old addresses remain in
    /// atomic slots until another stall reuses them, but no longer withhold
    /// write-TLB entries or consume the next episode's watch capacity.
    pub fn retire(self: *WatchSet) void {
        while (self.arming.cmpxchgWeak(0, 1, .acquire, .monotonic) != null) std.atomic.spinLoopHint();
        defer self.arming.store(0, .release);
        _ = self.epoch.fetchAdd(1, .acq_rel);
        self.count.store(0, .release);
        self.capacity_drops.store(0, .monotonic);
    }

    /// Count every write, but log the first few and exponentially spaced
    /// later ones for this address. A hot timestamp cannot silence a new
    /// queue watch, and a long stall still reports who writes occasionally.
    pub fn noteHit(self: *WatchSet, match: Match) bool {
        if (self.epoch.load(.acquire) != match.epoch or
            self.slot_epochs[match.index].load(.acquire) != match.epoch) return false;
        const hit = self.hits[match.index].fetchAdd(1, .monotonic) +| 1;
        return (hit <= initial_logged_hits or std.math.isPowerOfTwo(hit)) and
            self.epoch.load(.acquire) == match.epoch and
            self.slot_epochs[match.index].load(.acquire) == match.epoch;
    }
};

/// The PowerPC return address Xenia's x64 JIT stored just before a call:
/// `mov dword ptr [rsi+0x130], imm32` (`c7 86 30 01 00 00 imm32`), the
/// guest link register its emitter writes ahead of every `bl`. `bytes` ends
/// at the call instruction; the nearest such store wins.
pub fn xeniaGuestLinkBefore(bytes: []const u8) ?u32 {
    const pattern = [_]u8{ 0xC7, 0x86, 0x30, 0x01, 0x00, 0x00 };
    if (bytes.len < pattern.len + 4) return null;
    var start = bytes.len - (pattern.len + 4);
    while (true) {
        if (std.mem.eql(u8, bytes[start..][0..pattern.len], &pattern)) {
            return std.mem.readInt(u32, bytes[start + pattern.len ..][0..4], .little);
        }
        if (start == 0) return null;
        start -= 1;
    }
}

/// One frame of the guest stack Xenia's JIT keeps beside its context: the
/// host `rsp` at the call, the guest `r1`, and the guest link register at
/// function entry (`[ctx-40]` is the array, `[ctx-20]` its depth).
pub const StackPoint = struct { host_rsp: u64, r1: u32, lr: u32 };

pub fn decodeStackPoint(bytes: *const [16]u8) StackPoint {
    return .{
        .host_rsp = std.mem.readInt(u64, bytes[0..8], .little),
        .r1 = std.mem.readInt(u32, bytes[8..12], .little),
        .lr = std.mem.readInt(u32, bytes[12..16], .little),
    };
}

/// Whether a captured read is worth watching: guest memory, not the
/// spinner's own context block or guest stack frame.
pub fn watchCandidate(address: u64, membase: u64, context: u64, guest_r1: u64) bool {
    if (address < membase or address - membase >= (1 << 32)) return false;
    if (context != 0 and address +% 0x100 >= context and address < context +% 0x1000) return false;
    const guest = address - membase;
    if (guest_r1 != 0 and guest +% 0x400 >= guest_r1 and guest < guest_r1 +% 0x2000) return false;
    return true;
}

/// The guest memory reported around a polled address: a flag rarely means
/// anything alone. Halo 3's render thread polled one slot flag of a two-slot
/// queue on 2026-10-03; the producer's index, the consumer's index and the
/// other slot's flag sat within 0x40 bytes of it, and they are what says
/// whether producer and consumer still agree on the slot.
pub const neighborhood_bytes: u64 = 0x80;
pub const neighborhood_lead: u64 = 0x40;
pub const max_neighborhoods: usize = 6;

/// The windows worth dumping around a capture's polled addresses: each
/// starts `neighborhood_lead` before its address, 16-byte aligned, and a
/// window already covering an address absorbs it.
pub const Neighborhoods = struct {
    starts: [max_neighborhoods]u64 = undefined,
    len: usize = 0,

    pub fn add(self: *Neighborhoods, address: u64) void {
        for (self.starts[0..self.len]) |start| {
            if (address >= start and address - start < neighborhood_bytes) return;
        }
        if (self.len == max_neighborhoods) return;
        self.starts[self.len] = (address & ~@as(u64, 0xF)) -| neighborhood_lead;
        self.len += 1;
    }
};

test "the neighbourhoods of a queue's polled fields cover its indexes once" {
    // The 2026-10-03 render-queue reads: a slot flag, the slot count and the
    // consumer index. The producer index (+0x3C from the flag) and the
    // other slot's flag (+0x10) must fall inside a reported window.
    const base: u64 = 0x2_0000_0000;
    var windows = Neighborhoods{};
    windows.add(base + 0x8294_CAA8);
    windows.add(base + 0x8294_CB08);
    windows.add(base + 0x8294_CAE8);
    windows.add(base + 0x8294_CAA8);
    try std.testing.expectEqual(@as(usize, 2), windows.len);
    var covered_producer = false;
    var covered_other_slot = false;
    for (windows.starts[0..windows.len]) |start| {
        if (base + 0x8294_CAE4 >= start and base + 0x8294_CAE4 - start < neighborhood_bytes) covered_producer = true;
        if (base + 0x8294_CAB8 >= start and base + 0x8294_CAB8 - start < neighborhood_bytes) covered_other_slot = true;
    }
    try std.testing.expect(covered_producer and covered_other_slot);
    var full = Neighborhoods{};
    for (0..max_neighborhoods + 2) |index| full.add(base + index * 0x1000);
    try std.testing.expectEqual(max_neighborhoods, full.len);
}

test "a spin starts one capture once the frame count has stood still long enough" {
    var spin = ThreadSpin{};
    const second = std.time.ns_per_s;
    // The first PAUSE after a frame only stamps the time.
    try std.testing.expect(!spin.notePause(0x1000, 5, 1 * second));
    var pauses: u64 = 0;
    while (pauses < min_pauses) : (pauses += 1) {
        try std.testing.expect(!spin.notePause(0x1000, 5, null));
    }
    // Enough PAUSEs, not yet long enough.
    try std.testing.expect(!spin.notePause(0x1000, 5, 3 * second));
    try std.testing.expect(spin.notePause(0x1004, 5, 8 * second));
    try std.testing.expectEqual(capture_steps, spin.capture_remaining);
    try std.testing.expectEqual(@as(u64, 0x1004), spin.trigger_rip);
    // While capturing, and at the same frame count after it, nothing more.
    try std.testing.expect(!spin.notePause(0x1000, 5, 20 * second));
    spin.capture_remaining = 0;
    try std.testing.expect(!spin.notePause(0x1000, 5, 30 * second));
    // A new frame re-arms it and gives the next stall a full capture budget.
    try std.testing.expect(!spin.notePause(0x1000, 6, 31 * second));
    try std.testing.expectEqual(@as(u8, 0), spin.reports);
    spin.pauses_since_swap = min_pauses;
    try std.testing.expect(spin.notePause(0x1008, 6, 38 * second));
}

test "a long stalled frame is recaptured without exhausting later stalls" {
    var spin = ThreadSpin{};
    const second = std.time.ns_per_s;
    _ = spin.notePause(0x1000, 776, second);
    spin.pauses_since_swap = min_pauses;
    try std.testing.expect(spin.notePause(0x1004, 776, 8 * second));
    spin.capture_remaining = 0;
    try std.testing.expect(!spin.notePause(0x1004, 776, 20 * second));
    try std.testing.expect(spin.notePause(0x1008, 776, 39 * second));
    spin.capture_remaining = 0;
    try std.testing.expect(spin.notePause(0x100c, 776, 70 * second));
    spin.capture_remaining = 0;
    try std.testing.expect(!spin.notePause(0x1010, 776, 101 * second));
    try std.testing.expect(!spin.notePause(0x1010, 777, 102 * second));
    spin.pauses_since_swap = min_pauses;
    try std.testing.expect(spin.notePause(0x1014, 777, 109 * second));
}

test "a busy thread without PAUSE is captured at a stalled frame and rearmed by progress" {
    var spin = ThreadSpin{};
    const second = std.time.ns_per_s;
    try std.testing.expect(!spin.noteProgress(0x1000, 968, second));
    try std.testing.expect(!spin.noteProgress(0x1004, 968, 3 * second));
    try std.testing.expect(spin.noteProgress(0x1008, 968, 8 * second));
    try std.testing.expectEqual(@as(u64, 0), spin.pauses_since_swap);
    try std.testing.expectEqual(@as(u64, 0x1008), spin.trigger_rip);
    spin.capture_remaining = 0;
    try std.testing.expect(!spin.notePause(0x1010, 968, 9 * second));
    spin.pauses_since_swap = min_pauses;
    try std.testing.expect(!spin.notePause(0x1010, 968, 10 * second));
    try std.testing.expect(spin.noteProgress(0x1014, 968, 39 * second));
    spin.capture_remaining = 0;
    try std.testing.expect(!spin.noteProgress(0x1020, 969, 40 * second));
    try std.testing.expectEqual(@as(u8, 0), spin.reports);
    try std.testing.expect(spin.noteProgress(0x1024, 969, 47 * second));
}

test "progress sampling does not capture a busy boot before the first frame" {
    var spin = ThreadSpin{};
    try std.testing.expect(!spin.noteProgress(0x1000, 0, std.time.ns_per_s));
    try std.testing.expect(!spin.noteProgress(0x1000, 0, 60 * std.time.ns_per_s));
}

test "a stalled spinner asks for an assist once a second" {
    var spin = ThreadSpin{};
    const second = std.time.ns_per_s;
    _ = spin.notePause(0x1000, 9, 1 * second);
    spin.pauses_since_swap = min_pauses;
    try std.testing.expect(!spin.assistDue(9, 3 * second));
    try std.testing.expect(spin.assistDue(9, 8 * second));
    try std.testing.expect(!spin.assistDue(9, 8 * second + second / 2));
    try std.testing.expect(spin.assistDue(9, 9 * second + 1));
    // A new frame ends the stall.
    try std.testing.expect(!spin.assistDue(10, 20 * second));
}

test "no capture before the first frame" {
    var spin = ThreadSpin{};
    _ = spin.notePause(0x1000, 0, 1);
    var pauses: u64 = 0;
    while (pauses <= min_pauses) : (pauses += 1) _ = spin.notePause(0x1000, 0, null);
    try std.testing.expect(!spin.notePause(0x1000, 0, 100 * std.time.ns_per_s));
}

test "batched PAUSE accounting preserves the pause threshold and clock cadence" {
    var scalar = ThreadSpin{};
    var batched = ThreadSpin{};
    const second = std.time.ns_per_s;
    _ = scalar.notePause(0x1000, 12, second);
    _ = batched.notePauseBatch(0x1000, 12, second, 1);
    for (0..255) |_| _ = scalar.notePause(0x1000, 12, null);
    _ = batched.notePauseBatch(0x1000, 12, null, 255);
    try std.testing.expectEqual(scalar.pauses_since_swap, batched.pauses_since_swap);
    try std.testing.expect(scalar.wantsClock(12));
    try std.testing.expect(batched.wantsClockBatch(12, 1));
    try std.testing.expectEqual(scalar.capture_remaining, batched.capture_remaining);

    scalar.pauses_since_swap = min_pauses - 1;
    batched.pauses_since_swap = min_pauses - 1;
    try std.testing.expect(scalar.notePause(0x1004, 12, 8 * second));
    try std.testing.expect(batched.notePauseBatch(0x1004, 12, 8 * second, 1));
    try std.testing.expectEqual(scalar.trigger_rip, batched.trigger_rip);
    try std.testing.expectEqual(scalar.capture_remaining, batched.capture_remaining);
}

test "captured reads keep one record per address with the first and last value" {
    var spin = ThreadSpin{};
    spin.noteRead(0x10, 0x5000, 1, 0);
    spin.noteRead(0x10, 0x5000, 1, 2);
    spin.noteRead(0x14, 0x5004, 4, 7);
    try std.testing.expectEqual(@as(u32, 2), spin.capture_len);
    try std.testing.expectEqual(@as(u64, 0), spin.capture[0].first);
    try std.testing.expectEqual(@as(u64, 2), spin.capture[0].last);
    try std.testing.expectEqual(@as(u32, 2), spin.capture[0].count);
}

test "the watch set finds overlapping stores and watched pages" {
    var set = WatchSet{};
    try std.testing.expect(!set.armed());
    try std.testing.expectEqual(@as(?usize, 0), set.arm(0x1_4000_2ABD, 1, 0));
    try std.testing.expectEqual(@as(?usize, 0), set.arm(0x1_4000_2ABD, 1, 0));
    try std.testing.expect(set.armed());
    try std.testing.expectEqual(@as(?usize, 0), set.overlapping(0x1_4000_2ABC, 4));
    try std.testing.expectEqual(@as(?usize, null), set.overlapping(0x1_4000_2ABE, 2));
    try std.testing.expect(set.pageWatched(0x1_4000_2000, 0x1000));
    try std.testing.expect(!set.pageWatched(0x1_4000_3000, 0x1000));
    try std.testing.expect(set.noteHit(set.overlappingMatch(0x1_4000_2ABD, 1).?));
    try std.testing.expectEqual(@as(u64, 1), set.hits[0].load(.monotonic));
}

test "a hot watch cannot exhaust another watch's writer reports" {
    var set = WatchSet{};
    const clock = set.arm(0x1000, 4, 0).?;
    const queue = set.arm(0x2000, 4, 0).?;
    const clock_match = set.overlappingMatch(0x1000, 4).?;
    const queue_match = set.overlappingMatch(0x2000, 4).?;
    var clock_reports: u32 = 0;
    for (0..10_000) |_| {
        if (set.noteHit(clock_match)) clock_reports += 1;
    }
    try std.testing.expectEqual(@as(u64, 10_000), set.hits[clock].load(.monotonic));
    try std.testing.expect(clock_reports < 32);
    for (0..WatchSet.initial_logged_hits) |_| try std.testing.expect(set.noteHit(queue_match));
    try std.testing.expect(!set.noteHit(queue_match));
    for (0..6) |_| _ = set.noteHit(queue_match);
    try std.testing.expect(set.noteHit(queue_match)); // hit 16
    try std.testing.expectEqual(@as(u64, 16), set.hits[queue].load(.monotonic));
}

test "a present retires watches and restores capacity for the next stall" {
    var set = WatchSet{};
    const empty_epoch = set.epoch.load(.acquire);
    set.retire();
    try std.testing.expectEqual(@as(?usize, null), set.armForEpoch(empty_epoch, 0x5000, 4, 0));
    const stale_epoch = set.epoch.load(.acquire);
    for (0..WatchSet.capacity) |index| {
        try std.testing.expectEqual(@as(?usize, index), set.arm(0x1000 + index * 8, 4, 0));
    }
    try std.testing.expectEqual(@as(?usize, null), set.arm(0x4000, 4, 0));
    try std.testing.expectEqual(@as(u32, 1), set.capacity_drops.load(.monotonic));
    try std.testing.expect(set.pageWatched(0x1000, 0x1000));
    const old_match = set.overlappingMatch(0x1000, 4).?;
    set.retire();
    try std.testing.expect(!set.armed());
    try std.testing.expectEqual(@as(u32, 0), set.capacity_drops.load(.monotonic));
    try std.testing.expect(!set.pageWatched(0x1000, 0x1000));
    try std.testing.expectEqual(@as(?usize, null), set.overlapping(0x1000, 4));
    try std.testing.expect(!set.noteHit(old_match));
    try std.testing.expectEqual(@as(?usize, null), set.armForEpoch(stale_epoch, 0x5000, 4, 0));
    try std.testing.expectEqual(@as(?usize, 0), set.arm(0x4000, 4, 0));
    try std.testing.expectEqual(@as(?usize, null), set.overlapping(0x1000, 4));
    try std.testing.expectEqual(@as(?usize, 0), set.overlapping(0x4000, 4));
    try std.testing.expect(set.noteHit(set.overlappingMatch(0x4000, 4).?));
    try std.testing.expectEqual(@as(u64, 1), set.hits[0].load(.monotonic));
}

test "Xenia's link-register store is found before a call" {
    // mov dword [rsi+0x130], 0x825a7ed0 ; mov [rsi+0x134], edi ; mov rcx, [rsp+0x60]
    const bytes = [_]u8{ 0x90, 0xC7, 0x86, 0x30, 0x01, 0x00, 0x00, 0xD0, 0x7E, 0x5A, 0x82, 0x89, 0xBE, 0x34, 0x01, 0x00, 0x00, 0x48, 0x8B, 0x4C, 0x24, 0x60 };
    try std.testing.expectEqual(@as(?u32, 0x825A7ED0), xeniaGuestLinkBefore(&bytes));
    try std.testing.expectEqual(@as(?u32, null), xeniaGuestLinkBefore(bytes[11..]));
}

test "watch candidates leave out the context and the spinner's own stack frame" {
    const membase: u64 = 0x1_0000_0000;
    try std.testing.expect(watchCandidate(membase + 0x4000_2ABD, membase, 0x1_5000_0000, 0x7000_0000));
    try std.testing.expect(!watchCandidate(membase + 0x7000_0050, membase, 0x1_5000_0000, 0x7000_0000));
    try std.testing.expect(!watchCandidate(0x1_5000_0030, membase, 0x1_5000_0000, 0x7000_0000));
    try std.testing.expect(!watchCandidate(0x4000, membase, 0, 0));
}
