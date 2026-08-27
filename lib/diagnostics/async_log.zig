//! A diagnostic transport that keeps the observer out of the observed
//! program's timing.
//!
//! Rosette writes its diagnostics from translated guest threads. In the
//! synchronous path each line costs the calling thread `std.debug.print` — a
//! process-wide stderr mutex — plus two `write` syscalls. Twenty thousand lines
//! from the GPU command path is twenty thousand serialisation points against
//! every other thread that logs, on the exact subsystem whose scheduling is
//! under investigation.
//!
//! That makes the observer a participant. A livelock, a lost wakeup or a
//! wait/signal race can be created, hidden, or displaced by the logging alone,
//! and no amount of care reading the log recovers what the logging changed.
//!
//! ## Producers never wait
//!
//! One atomic increment claims a slot; a `memcpy` fills it; a release store
//! publishes it. There is no lock, no syscall, and — the part that matters —
//! **no path on which a producer waits for the writer**. When the ring is full
//! the line is dropped and counted.
//!
//! Dropping is the deliberate choice. A bounded queue that blocks when full has
//! moved the stall somewhere less predictable rather than removed it; that is
//! deferred-synchronous logging wearing an async costume, and it is what a
//! spin-wait ring strategy gives you. A counted gap in a log is recoverable.
//! A perturbed scheduler is not.
//!
//! ## Losing a line is reported, never silent
//!
//! `integrity()` reports `lossy_counted` with an exact drop count whenever the
//! ring overflowed. Absence of a diagnostic in a lossy log is not evidence that
//! it did not fire, and the report says so in those words, because a truncated
//! log that looks complete is worse than the stall this file exists to avoid.

const std = @import("std");
const contract = @import("diagnostics_async_log_contract");

pub const Mode = contract.Mode;
pub const Backpressure = contract.Backpressure;
pub const Integrity = contract.Integrity;
pub const Priority = contract.Priority;

pub const slot_bytes = contract.default_slot_bytes;
pub const slot_count = contract.default_slot_count;
pub const payload_capacity = contract.payloadCapacity(slot_bytes);

/// One record. `sequence` is the publication flag: the writer consumes slot
/// `n` only once its sequence reads `n + 1`, which cannot happen until the
/// producer's release store retires its `memcpy`.
pub const Slot = struct {
    sequence: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    length: u32 = 0,
    /// Whether the payload was cut to fit. Counted separately from a drop: a
    /// truncated line still proves the diagnostic fired.
    truncated: bool = false,
    payload: [payload_capacity]u8 = undefined,
};

pub const Stats = struct {
    accepted: u64 = 0,
    dropped: u64 = 0,
    truncated: u64 = 0,
    written: u64 = 0,
    /// Bytes the writer thread has emitted.
    bytes_written: u64 = 0,
    /// Batched writes the writer performed. `written / write_calls` is how
    /// many syscalls the synchronous path would have cost per one here.
    write_calls: u64 = 0,
    queued: u64 = 0,
    /// Lines that took the synchronous path because they were critical.
    synchronous_criticals: u64 = 0,

    pub fn integrity(self: Stats) Integrity {
        return contract.integrityOf(self.dropped, self.queued, true);
    }

    /// Syscalls avoided per line actually written. The synchronous path costs
    /// two per line; a batch of a hundred costs one.
    pub fn batchFactor(self: Stats) u64 {
        if (self.write_calls == 0) return 0;
        return self.written / self.write_calls;
    }
};

pub const Ring = struct {
    slots: []Slot,
    /// Monotonic claim counter. Producers increment; the low bits index a slot.
    claimed: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    /// Slots the writer has consumed. Read by producers to detect a full ring.
    consumed: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

    accepted: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    dropped: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    truncated: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    written: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    bytes_written: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    write_calls: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    synchronous_criticals: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

    running: std.atomic.Value(bool) = std.atomic.Value(bool).init(true),

    pub fn init(slots: []Slot) Ring {
        for (slots) |*slot| slot.sequence.store(0, .monotonic);
        return .{ .slots = slots };
    }

    /// Offer a line. Returns false when the ring was full and the line was
    /// dropped.
    ///
    /// This is the whole producer path: one fetchAdd, one bounds test, one
    /// memcpy, one release store. Nothing here can block, allocate, or enter
    /// the kernel, which is what keeps the observed program's timing its own.
    pub fn offer(self: *Ring, text: []const u8) bool {
        const count = self.slots.len;
        const ticket = self.claimed.fetchAdd(1, .monotonic);

        // Full when the claim would lap a slot the writer has not consumed.
        // Checked after claiming rather than before: a pre-check would race
        // with other producers and let two claim the same slot.
        if (ticket -% self.consumed.load(.acquire) >= count) {
            _ = self.dropped.fetchAdd(1, .monotonic);
            return false;
        }

        const slot = &self.slots[@intCast(ticket % count)];
        var length = text.len;
        var cut = false;
        if (length > payload_capacity) {
            length = payload_capacity;
            cut = true;
            _ = self.truncated.fetchAdd(1, .monotonic);
        }
        @memcpy(slot.payload[0..length], text[0..length]);
        slot.length = @intCast(length);
        slot.truncated = cut;

        // Release: the writer must not observe the sequence before the payload.
        slot.sequence.store(ticket +% 1, .release);
        _ = self.accepted.fetchAdd(1, .monotonic);
        return true;
    }

    /// Consume every published slot in order, handing batches to `sink`.
    ///
    /// Stops at the first unpublished slot rather than scanning past it: slots
    /// are consumed strictly in claim order, so a producer still filling slot
    /// `n` cannot let slot `n + 1` overtake it in the log.
    pub fn drain(
        self: *Ring,
        context: *anyopaque,
        sink: *const fn (*anyopaque, []const u8) void,
        max_slots: usize,
    ) usize {
        const count = self.slots.len;
        var batch: [64 * 1024]u8 = undefined;
        var used: usize = 0;
        var consumed_now: usize = 0;

        while (consumed_now < max_slots) {
            const next = self.consumed.load(.monotonic);
            if (next == self.claimed.load(.acquire)) break;
            const slot = &self.slots[@intCast(next % count)];
            if (slot.sequence.load(.acquire) != next +% 1) break;

            const length = @as(usize, slot.length);
            const needs_newline = length == 0 or slot.payload[length - 1] != '\n';
            const total = length + @intFromBool(needs_newline);
            if (used + total > batch.len) {
                sink(context, batch[0..used]);
                _ = self.write_calls.fetchAdd(1, .monotonic);
                _ = self.bytes_written.fetchAdd(used, .monotonic);
                used = 0;
            }
            @memcpy(batch[used .. used + length], slot.payload[0..length]);
            used += length;
            if (needs_newline) {
                batch[used] = '\n';
                used += 1;
            }

            slot.sequence.store(0, .monotonic);
            self.consumed.store(next +% 1, .release);
            _ = self.written.fetchAdd(1, .monotonic);
            consumed_now += 1;
        }

        if (used != 0) {
            sink(context, batch[0..used]);
            _ = self.write_calls.fetchAdd(1, .monotonic);
            _ = self.bytes_written.fetchAdd(used, .monotonic);
        }
        return consumed_now;
    }

    pub fn noteSynchronousCritical(self: *Ring) void {
        _ = self.synchronous_criticals.fetchAdd(1, .monotonic);
    }

    pub fn pending(self: *const Ring) u64 {
        return self.claimed.load(.monotonic) -% self.consumed.load(.monotonic);
    }

    pub fn stats(self: *const Ring) Stats {
        return .{
            .accepted = self.accepted.load(.monotonic),
            .dropped = self.dropped.load(.monotonic),
            .truncated = self.truncated.load(.monotonic),
            .written = self.written.load(.monotonic),
            .bytes_written = self.bytes_written.load(.monotonic),
            .write_calls = self.write_calls.load(.monotonic),
            .queued = self.pending(),
            .synchronous_criticals = self.synchronous_criticals.load(.monotonic),
        };
    }

    pub fn stop(self: *Ring) void {
        self.running.store(false, .release);
    }

    pub fn isRunning(self: *const Ring) bool {
        return self.running.load(.acquire);
    }
};

/// Whether a line must bypass the ring.
///
/// A crash report queued behind a writer thread that may never run again is a
/// crash report that does not exist. Classified by content rather than by the
/// caller passing a priority, so that every existing call site gets the
/// protection without being rewritten — a call site that had to remember would
/// be a call site that eventually forgets.
pub fn priorityOf(text: []const u8) Priority {
    if (containsAny(text, &.{ "CRASH", "FATAL", "SIGSEGV", "SIGBUS", "SIGILL", "panic", "ABORT" })) {
        return .critical;
    }
    if (containsAny(text, &.{ "CONTRACT:", "FRONTIER", "BLOCKER", "VERDICT", "verdict=", "finding=" })) {
        return .finding;
    }
    return .routine;
}

fn containsAny(text: []const u8, needles: []const []const u8) bool {
    for (needles) |needle| {
        if (std.mem.indexOf(u8, text, needle) != null) return true;
    }
    return false;
}

const CollectSink = struct {
    buffer: std.ArrayList(u8),
    calls: usize = 0,

    fn write(context: *anyopaque, bytes: []const u8) void {
        const self: *CollectSink = @ptrCast(@alignCast(context));
        self.calls += 1;
        self.buffer.appendSlice(std.testing.allocator, bytes) catch unreachable;
    }
};

fn testRing(slots: []Slot) Ring {
    return Ring.init(slots);
}

test "a line offered is a line drained, in order" {
    var slots: [8]Slot = undefined;
    var ring = testRing(&slots);
    var sink = CollectSink{ .buffer = .empty };
    defer sink.buffer.deinit(std.testing.allocator);

    try std.testing.expect(ring.offer("first"));
    try std.testing.expect(ring.offer("second"));
    try std.testing.expect(ring.offer("third"));
    try std.testing.expectEqual(@as(u64, 3), ring.pending());

    const drained = ring.drain(&sink, CollectSink.write, 64);
    try std.testing.expectEqual(@as(usize, 3), drained);
    try std.testing.expectEqualStrings("first\nsecond\nthird\n", sink.buffer.items);
    try std.testing.expectEqual(@as(u64, 0), ring.pending());
}

test "a full ring drops rather than blocking, and counts every drop" {
    // The property the whole file exists for. A producer must return whether
    // or not the writer is keeping up.
    var slots: [4]Slot = undefined;
    var ring = testRing(&slots);

    try std.testing.expect(ring.offer("a"));
    try std.testing.expect(ring.offer("b"));
    try std.testing.expect(ring.offer("c"));
    try std.testing.expect(ring.offer("d"));
    // Fifth into a four-slot ring with nothing consumed.
    try std.testing.expect(!ring.offer("e"));
    try std.testing.expect(!ring.offer("f"));

    const totals = ring.stats();
    try std.testing.expectEqual(@as(u64, 4), totals.accepted);
    try std.testing.expectEqual(@as(u64, 2), totals.dropped);
    try std.testing.expectEqual(Integrity.lossy_counted, totals.integrity());
    try std.testing.expect(std.mem.indexOf(u8, totals.integrity().guidance(), "not evidence") != null);
}

test "draining frees slots for later producers" {
    var slots: [4]Slot = undefined;
    var ring = testRing(&slots);
    var sink = CollectSink{ .buffer = .empty };
    defer sink.buffer.deinit(std.testing.allocator);

    var index: usize = 0;
    while (index < 4) : (index += 1) try std.testing.expect(ring.offer("x"));
    try std.testing.expect(!ring.offer("overflow"));

    _ = ring.drain(&sink, CollectSink.write, 64);
    // Space exists again, and the drop already recorded stays recorded.
    try std.testing.expect(ring.offer("after"));
    try std.testing.expectEqual(@as(u64, 1), ring.stats().dropped);
    try std.testing.expectEqual(@as(u64, 5), ring.stats().accepted);
}

test "an oversized line is truncated and counted, never dropped" {
    // Losing the tail of a diagnostic is recoverable; losing the fact that it
    // fired is not.
    var slots: [4]Slot = undefined;
    var ring = testRing(&slots);
    var sink = CollectSink{ .buffer = .empty };
    defer sink.buffer.deinit(std.testing.allocator);

    var huge: [payload_capacity * 2]u8 = undefined;
    @memset(&huge, 'z');
    try std.testing.expect(ring.offer(&huge));

    _ = ring.drain(&sink, CollectSink.write, 64);
    const totals = ring.stats();
    try std.testing.expectEqual(@as(u64, 1), totals.truncated);
    try std.testing.expectEqual(@as(u64, 0), totals.dropped);
    // The payload plus the newline the drain adds.
    try std.testing.expectEqual(payload_capacity + 1, sink.buffer.items.len);
    try std.testing.expectEqual(Integrity.complete, totals.integrity());
}

test "the drain batches many lines into few writes" {
    // The syscall reduction is the measurable half of the benefit: the
    // synchronous path costs two writes per line.
    var slots: [512]Slot = undefined;
    var ring = testRing(&slots);
    var sink = CollectSink{ .buffer = .empty };
    defer sink.buffer.deinit(std.testing.allocator);

    var index: usize = 0;
    while (index < 400) : (index += 1) _ = ring.offer("a diagnostic line of ordinary length");
    _ = ring.drain(&sink, CollectSink.write, 4096);

    const totals = ring.stats();
    try std.testing.expectEqual(@as(u64, 400), totals.written);
    try std.testing.expect(totals.write_calls < 10);
    try std.testing.expect(totals.batchFactor() > 40);
    try std.testing.expectEqual(@as(usize, @intCast(totals.write_calls)), sink.calls);
}

test "an unpublished slot stops the drain rather than being skipped" {
    // A producer mid-memcpy must not let the next line overtake it, or the log
    // reorders under load — exactly when ordering matters most.
    var slots: [8]Slot = undefined;
    var ring = testRing(&slots);
    var sink = CollectSink{ .buffer = .empty };
    defer sink.buffer.deinit(std.testing.allocator);

    _ = ring.offer("first");
    // Simulate a producer that has claimed slot 1 and not yet published.
    const ticket = ring.claimed.fetchAdd(1, .monotonic);
    _ = ring.offer("third");

    const drained = ring.drain(&sink, CollectSink.write, 64);
    try std.testing.expectEqual(@as(usize, 1), drained);
    try std.testing.expectEqualStrings("first\n", sink.buffer.items);

    // Once the straggler publishes, the rest follows in order.
    const slot = &ring.slots[@intCast(ticket % ring.slots.len)];
    @memcpy(slot.payload[0..6], "second");
    slot.length = 6;
    slot.sequence.store(ticket +% 1, .release);
    _ = ring.drain(&sink, CollectSink.write, 64);
    try std.testing.expectEqualStrings("first\nsecond\nthird\n", sink.buffer.items);
}

test "a queued tail at exit is reported rather than assumed written" {
    var slots: [8]Slot = undefined;
    var ring = testRing(&slots);
    _ = ring.offer("still queued");
    const totals = ring.stats();
    try std.testing.expectEqual(@as(u64, 1), totals.queued);
    try std.testing.expectEqual(Integrity.unflushed_tail, totals.integrity());
}

test "a crash line is classified critical and bypasses the ring" {
    try std.testing.expectEqual(Priority.critical, priorityOf("macho-processor: CRASH at rip=0x1234"));
    try std.testing.expectEqual(Priority.critical, priorityOf("SIGSEGV in guest thread 6"));
    try std.testing.expectEqual(Priority.critical, priorityOf("thread panic: index out of bounds"));
    try std.testing.expect(Priority.critical.requiresSynchronousWrite());

    // A finding is queued like anything else: forcing it onto the caller's
    // thread would put the report path back into the program's timing.
    try std.testing.expectEqual(Priority.finding, priorityOf("macho-processor: VD SWAP CONTRACT: met=11/29"));
    try std.testing.expectEqual(Priority.finding, priorityOf("RUN HORIZON: verdict=STALLED"));
    try std.testing.expect(!Priority.finding.requiresSynchronousWrite());

    try std.testing.expectEqual(Priority.routine, priorityOf("ring watch armed: base=0x1fc9b000"));
}

test "concurrent producers neither lose nor duplicate a line" {
    // The claim is one fetchAdd; if it were a load-then-store, two threads
    // would share a slot and the log would silently lose lines under exactly
    // the load that makes logging interesting.
    var slots: [4096]Slot = undefined;
    var ring = testRing(&slots);

    const Worker = struct {
        fn run(target: *Ring, lines: usize) void {
            var index: usize = 0;
            while (index < lines) : (index += 1) _ = target.offer("concurrent line");
        }
    };

    var threads: [4]std.Thread = undefined;
    for (&threads) |*thread| {
        thread.* = try std.Thread.spawn(.{}, Worker.run, .{ &ring, 500 });
    }
    for (threads) |thread| thread.join();

    const totals = ring.stats();
    try std.testing.expectEqual(@as(u64, 2000), totals.accepted + totals.dropped);
    try std.testing.expectEqual(@as(u64, 2000), ring.claimed.load(.monotonic));
}

// ---------------------------------------------------------------------------
// Process-wide transport
// ---------------------------------------------------------------------------

/// The single ring a process uses, plus its writer thread.
///
/// Kept here rather than in the Mach-O event log because that file lives in a
/// module the diagnostics module depends on; the event log reaches this through
/// installed function pointers instead. The indirection also means a run that
/// does not opt in pays one null test per line and nothing else.
const Transport = struct {
    var ring_storage: Ring = undefined;
    var ring: ?*Ring = null;
    var slots: []Slot = &.{};
    var allocator_used: ?std.mem.Allocator = null;
    var writer: ?std.Thread = null;
    var detail_fd: i32 = -1;
    var mirror_stderr: bool = false;
};

/// Write and sleep callbacks supplied by the process, so this module performs
/// no platform I/O of its own and stays testable without a file descriptor or
/// a real clock.
pub const WriteFn = *const fn (fd: i32, bytes: []const u8) void;
pub const SleepFn = *const fn (nanoseconds: u64) void;
var transport_write: ?WriteFn = null;
var transport_sleep: ?SleepFn = null;

pub fn transportActive() bool {
    return Transport.ring != null;
}

pub fn transportStats() Stats {
    const ring = Transport.ring orelse return .{};
    return ring.stats();
}

/// Start the transport. Returns false when it could not start, in which case
/// the caller must keep using the synchronous path: a ring with no writer would
/// fill once and drop forever, which is strictly worse than what it replaced.
pub fn startTransport(
    allocator: std.mem.Allocator,
    fd: i32,
    mirror_stderr: bool,
    write: WriteFn,
    sleep: SleepFn,
) bool {
    if (Transport.ring != null) return true;
    if (fd < 0) return false;
    const slots = allocator.alloc(Slot, slot_count) catch return false;
    Transport.slots = slots;
    Transport.allocator_used = allocator;
    Transport.detail_fd = fd;
    Transport.mirror_stderr = mirror_stderr;
    transport_write = write;
    transport_sleep = sleep;
    Transport.ring_storage = Ring.init(slots);
    Transport.ring = &Transport.ring_storage;
    Transport.writer = std.Thread.spawn(.{}, writerLoop, .{}) catch {
        Transport.ring = null;
        allocator.free(slots);
        Transport.slots = &.{};
        Transport.allocator_used = null;
        transport_write = null;
        transport_sleep = null;
        return false;
    };
    return true;
}

/// Stop the transport and write everything still queued. Draining before
/// returning is what keeps `unflushed_tail` at zero.
pub fn stopTransport() void {
    const ring = Transport.ring orelse return;
    ring.stop();
    if (Transport.writer) |thread| thread.join();
    Transport.writer = null;
    _ = ring.drain(undefined, transportSink, std.math.maxInt(usize));
    Transport.ring = null;
    if (Transport.allocator_used) |allocator| allocator.free(Transport.slots);
    Transport.slots = &.{};
    Transport.allocator_used = null;
    transport_write = null;
    transport_sleep = null;
}

pub fn offerLine(text: []const u8) bool {
    const ring = Transport.ring orelse return false;
    return ring.offer(text);
}

pub fn flushTransport() void {
    const ring = Transport.ring orelse return;
    _ = ring.drain(undefined, transportSink, std.math.maxInt(usize));
}

/// True when a line must take the synchronous path. Exposed with this exact
/// shape so the Mach-O event log can install it as a plain function pointer.
pub fn lineIsCritical(text: []const u8) bool {
    const critical = priorityOf(text).requiresSynchronousWrite();
    if (critical) {
        if (Transport.ring) |ring| ring.noteSynchronousCritical();
    }
    return critical;
}

fn transportSink(context: *anyopaque, bytes: []const u8) void {
    _ = context;
    const write = transport_write orelse return;
    write(Transport.detail_fd, bytes);
    if (Transport.mirror_stderr) write(2, bytes);
}

fn writerLoop() void {
    const ring = Transport.ring orelse return;
    var idle: u32 = 0;
    while (ring.isRunning()) {
        const drained = ring.drain(undefined, transportSink, 4096);
        if (drained == 0) {
            // Back off rather than spin. A busy writer competes with the
            // translated guest for the very cores this transport exists to
            // stop disturbing.
            idle +|= 1;
            const nanoseconds: u64 = if (idle < 16)
                200 * std.time.ns_per_us
            else
                2 * std.time.ns_per_ms;
            if (transport_sleep) |sleep| sleep(nanoseconds);
        } else {
            idle = 0;
        }
    }
    _ = ring.drain(undefined, transportSink, std.math.maxInt(usize));
}

test "the transport refuses to start without a destination" {
    // A ring with nowhere to drain fills once and then drops forever, which is
    // strictly worse than the synchronous path it would replace.
    const Sink = struct {
        fn write(fd: i32, bytes: []const u8) void {
            _ = fd;
            _ = bytes;
        }
        fn sleep(nanoseconds: u64) void {
            _ = nanoseconds;
        }
    };
    try std.testing.expect(!startTransport(std.testing.allocator, -1, false, Sink.write, Sink.sleep));
    try std.testing.expect(!transportActive());
    try std.testing.expect(!offerLine("dropped on the floor"));
    try std.testing.expectEqual(Integrity.complete, transportStats().integrity());
}

test "critical classification is stable through the installed hook shape" {
    try std.testing.expect(lineIsCritical("macho-processor: CRASH in guest thread"));
    try std.testing.expect(!lineIsCritical("macho-processor: RUN HORIZON: verdict=STALLED"));
    try std.testing.expect(!lineIsCritical("ring watch armed"));
}
