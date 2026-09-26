//! A watchdog thread that notices when the process stops making progress,
//! and says who is waiting on what when it does.
//!
//! Every Xenia run so far has ended on the operator's SIGTERM, and a hung
//! run's last log line is whatever it happened to be doing when it stopped.
//! On 2026-09-25 that line was the AppKit bridge announcing a main-thread
//! request; the ninety seconds of deadlock after it said nothing. The
//! watchdog runs on its own host thread, is never part of guest execution,
//! and reads only lock-free state (the gate's snapshot and `watch.zig`'s
//! records), so it can report while every guest thread is asleep - once per
//! stall episode, before any supervisor gives up.

const std = @import("std");
const futex = @import("futex.zig");
const watch = @import("watch.zig");
const safepoint = @import("safepoint.zig");
const Mutex = @import("mutex.zig").Mutex;
const EpochEvent = @import("event.zig").EpochEvent;

pub const Kind = enum {
    /// A stop-the-world has been held, or taken, for longer than the
    /// threshold: a thread holding it is blocked on something.
    stop_the_world_stuck,
    /// Nothing the embedder counts as progress has moved for the threshold.
    no_progress,
    /// The watched lock has had one holder, without a single release, for
    /// longer than `lock_hold_threshold_ns`: every other thread that needs it
    /// is queued behind whatever that holder is doing. Progress elsewhere
    /// does not hide this one.
    lock_held,
};

pub const Report = struct {
    kind: Kind,
    /// Time since progress last moved.
    stalled_ns: u64,
    progress: u64,
    gate: ?safepoint.Snapshot,
    now_ns: u64,
    /// For `lock_held`: the holder's thread id and how long it has held.
    lock_holder: u64 = 0,
    lock_held_ns: u64 = 0,
};

/// One periodic look at the process, for an embedder that wants a record of
/// who was doing what even when nothing is wrong.
pub const Pulse = struct {
    sequence: u64,
    now_ns: u64,
    /// Since the watchdog started.
    elapsed_ns: u64,
    progress: u64,
    /// The watched lock's holder now (zero when free), and whether it has had
    /// that holder without a release since the previous tick.
    lock_holder: u64 = 0,
    lock_held_ns: u64 = 0,
};

pub const Config = struct {
    interval_ns: u64 = std.time.ns_per_s,
    threshold_ns: u64 = 10 * std.time.ns_per_s,
    /// Zero turns the pulse off.
    pulse_interval_ns: u64 = 0,
    lock_hold_threshold_ns: u64 = 5 * std.time.ns_per_s,
};

/// How long the watched lock has had its current holder without a release,
/// from samples taken once per tick. Costs the lock nothing: its holder and
/// acquisition count are fields it already maintains.
const LockTracker = struct {
    holder: u64 = 0,
    acquisitions: u64 = 0,
    since_ns: u64 = 0,
    reported: bool = false,

    fn sample(self: *LockTracker, lock: *const Mutex, now: u64) u64 {
        const holder = lock.holder.load(.monotonic);
        const acquisitions = lock.stats.acquisitions.load(.monotonic);
        if (holder == 0) {
            self.* = .{};
            return 0;
        }
        if (holder != self.holder or acquisitions != self.acquisitions) {
            self.* = .{ .holder = holder, .acquisitions = acquisitions, .since_ns = now };
            return 0;
        }
        return now -| self.since_ns;
    }
};

pub const Watchdog = struct {
    config: Config = .{},
    context: ?*anyopaque = null,
    /// Called on the watchdog thread, once per stall episode.
    report: *const fn (?*anyopaque, *const Report) void,
    /// Total progress (guest instructions retired, frames, ...).
    progress: *const fn (?*anyopaque) u64,
    gate: ?*safepoint.Gate = null,
    /// A lock whose long holds are a finding in their own right.
    lock: ?*const Mutex = null,
    /// Called on the watchdog thread every `pulse_interval_ns`.
    pulse: ?*const fn (?*anyopaque, *const Pulse) void = null,
    thread: ?std.Thread = null,
    stop_requested: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    wake: EpochEvent = EpochEvent.init("watchdog interval"),
    reports: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),

    pub fn start(self: *Watchdog) !void {
        if (self.thread != null) return;
        self.stop_requested.store(false, .release);
        self.thread = try std.Thread.spawn(.{}, run, .{self});
    }

    pub fn stop(self: *Watchdog) void {
        const thread = self.thread orelse return;
        self.stop_requested.store(true, .release);
        self.wake.notify();
        thread.join();
        self.thread = null;
    }

    fn run(self: *Watchdog) void {
        _ = watch.registerCurrentThread("rosette stall watchdog");
        defer watch.unregisterCurrentThread();
        var last_progress = self.progress(self.context);
        const started = futex.monotonicNanoseconds();
        var last_change = started;
        var reported = false;
        var lock_tracker: LockTracker = .{};
        var next_pulse = started +| self.config.pulse_interval_ns;
        var pulses: u64 = 0;
        // The tick is the shorter of the stall interval and the pulse, so a
        // pulse is never late by more than one tick.
        const tick_ns = if (self.config.pulse_interval_ns != 0)
            @min(self.config.interval_ns, self.config.pulse_interval_ns)
        else
            self.config.interval_ns;
        while (!self.stop_requested.load(.acquire)) {
            const observed = self.wake.current();
            if (self.stop_requested.load(.acquire)) break;
            _ = self.wake.waitChange(observed, futex.monotonicNanoseconds() + tick_ns);
            if (self.stop_requested.load(.acquire)) break;

            const now = futex.monotonicNanoseconds();
            const progress = self.progress(self.context);
            if (progress != last_progress) {
                last_progress = progress;
                last_change = now;
                reported = false;
            }
            const lock_held_ns = if (self.lock) |lock| lock_tracker.sample(lock, now) else 0;
            if (self.pulse) |pulse| {
                if (self.config.pulse_interval_ns != 0 and now >= next_pulse) {
                    next_pulse = now +| self.config.pulse_interval_ns;
                    pulses += 1;
                    const snapshot: Pulse = .{
                        .sequence = pulses,
                        .now_ns = now,
                        .elapsed_ns = now -| started,
                        .progress = progress,
                        .lock_holder = lock_tracker.holder,
                        .lock_held_ns = lock_held_ns,
                    };
                    pulse(self.context, &snapshot);
                }
            }
            if (lock_held_ns >= self.config.lock_hold_threshold_ns and !lock_tracker.reported) {
                lock_tracker.reported = true;
                _ = self.reports.fetchAdd(1, .monotonic);
                const finding: Report = .{
                    .kind = .lock_held,
                    .stalled_ns = now -| last_change,
                    .progress = progress,
                    .gate = if (self.gate) |gate| gate.snapshot() else null,
                    .now_ns = now,
                    .lock_holder = lock_tracker.holder,
                    .lock_held_ns = lock_held_ns,
                };
                self.report(self.context, &finding);
            }
            const gate_snapshot: ?safepoint.Snapshot = if (self.gate) |gate| gate.snapshot() else null;
            const stuck_stop = if (gate_snapshot) |snapshot|
                snapshot.stopping and snapshot.held_for_ns >= self.config.threshold_ns
            else
                false;
            const stalled_ns = now -| last_change;
            if (reported) continue;
            const kind: Kind = if (stuck_stop)
                .stop_the_world_stuck
            else if (stalled_ns >= self.config.threshold_ns)
                .no_progress
            else
                continue;
            reported = true;
            _ = self.reports.fetchAdd(1, .monotonic);
            const finding: Report = .{
                .kind = kind,
                .stalled_ns = stalled_ns,
                .progress = progress,
                .gate = gate_snapshot,
                .now_ns = now,
            };
            self.report(self.context, &finding);
        }
    }
};

test "a stalled embedder is reported once, and progress re-arms the report" {
    const Embedder = struct {
        progress_value: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        reports: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
        last_kind: std.atomic.Value(u8) = std.atomic.Value(u8).init(0xFF),

        fn progress(context: ?*anyopaque) u64 {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            return self.progress_value.load(.acquire);
        }

        fn report(context: ?*anyopaque, finding: *const Report) void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.last_kind.store(@intFromEnum(finding.kind), .release);
            _ = self.reports.fetchAdd(1, .acq_rel);
        }
    };
    var embedder: Embedder = .{};
    var watchdog: Watchdog = .{
        .config = .{ .interval_ns = 2 * std.time.ns_per_ms, .threshold_ns = 10 * std.time.ns_per_ms },
        .context = &embedder,
        .report = Embedder.report,
        .progress = Embedder.progress,
    };
    try watchdog.start();
    defer watchdog.stop();

    const deadline = futex.monotonicNanoseconds() + 2 * std.time.ns_per_s;
    while (embedder.reports.load(.acquire) == 0 and futex.monotonicNanoseconds() < deadline) {
        var pause = std.c.timespec{ .sec = 0, .nsec = std.time.ns_per_ms };
        _ = std.c.nanosleep(&pause, null);
    }
    try std.testing.expectEqual(@as(u32, 1), embedder.reports.load(.acquire));
    try std.testing.expectEqual(@intFromEnum(Kind.no_progress), embedder.last_kind.load(.acquire));
    // Still stalled: no second report for the same episode.
    var pause = std.c.timespec{ .sec = 0, .nsec = 30 * std.time.ns_per_ms };
    _ = std.c.nanosleep(&pause, null);
    try std.testing.expectEqual(@as(u32, 1), embedder.reports.load(.acquire));
}

test "a stop-the-world held past the threshold is named as such" {
    const Embedder = struct {
        tick: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        kind: std.atomic.Value(u8) = std.atomic.Value(u8).init(0xFF),

        fn progress(context: ?*anyopaque) u64 {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            // Progress keeps moving: only the held stop is a finding.
            return self.tick.fetchAdd(1, .acq_rel);
        }

        fn report(context: ?*anyopaque, finding: *const Report) void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.kind.store(@intFromEnum(finding.kind), .release);
        }
    };
    const gate = try std.testing.allocator.create(safepoint.Gate);
    defer std.testing.allocator.destroy(gate);
    gate.* = .{};
    var embedder: Embedder = .{};
    var watchdog: Watchdog = .{
        .config = .{ .interval_ns = 2 * std.time.ns_per_ms, .threshold_ns = 10 * std.time.ns_per_ms },
        .context = &embedder,
        .report = Embedder.report,
        .progress = Embedder.progress,
        .gate = gate,
    };
    var mutation = gate.enterMutation();
    try watchdog.start();
    const deadline = futex.monotonicNanoseconds() + 2 * std.time.ns_per_s;
    while (embedder.kind.load(.acquire) == 0xFF and futex.monotonicNanoseconds() < deadline) {
        var pause = std.c.timespec{ .sec = 0, .nsec = std.time.ns_per_ms };
        _ = std.c.nanosleep(&pause, null);
    }
    watchdog.stop();
    mutation.unlock();
    try std.testing.expectEqual(@intFromEnum(Kind.stop_the_world_stuck), embedder.kind.load(.acquire));
}

test "a lock held past its threshold is reported once, naming its holder, while progress moves" {
    const Embedder = struct {
        tick: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        kind: std.atomic.Value(u8) = std.atomic.Value(u8).init(0xFF),
        holder: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        reports: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),

        fn progress(context: ?*anyopaque) u64 {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            return self.tick.fetchAdd(1, .acq_rel);
        }

        fn report(context: ?*anyopaque, finding: *const Report) void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.kind.store(@intFromEnum(finding.kind), .release);
            self.holder.store(finding.lock_holder, .release);
            _ = self.reports.fetchAdd(1, .acq_rel);
        }
    };
    var lock = Mutex.init("watched");
    var embedder: Embedder = .{};
    var watchdog: Watchdog = .{
        .config = .{
            .interval_ns = 2 * std.time.ns_per_ms,
            .threshold_ns = std.time.ns_per_s,
            .lock_hold_threshold_ns = 10 * std.time.ns_per_ms,
        },
        .context = &embedder,
        .report = Embedder.report,
        .progress = Embedder.progress,
        .lock = &lock,
    };
    lock.lock();
    try watchdog.start();
    const deadline = futex.monotonicNanoseconds() + 2 * std.time.ns_per_s;
    while (embedder.reports.load(.acquire) == 0 and futex.monotonicNanoseconds() < deadline) {
        var pause = std.c.timespec{ .sec = 0, .nsec = std.time.ns_per_ms };
        _ = std.c.nanosleep(&pause, null);
    }
    var pause = std.c.timespec{ .sec = 0, .nsec = 30 * std.time.ns_per_ms };
    _ = std.c.nanosleep(&pause, null);
    watchdog.stop();
    lock.unlock();
    try std.testing.expectEqual(@as(u32, 1), embedder.reports.load(.acquire));
    try std.testing.expectEqual(@intFromEnum(Kind.lock_held), embedder.kind.load(.acquire));
    try std.testing.expectEqual(@import("mutex.zig").currentThreadId(), embedder.holder.load(.acquire));
}

test "a lock that keeps changing hands is never reported as held" {
    const Embedder = struct {
        reports: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
        fn progress(_: ?*anyopaque) u64 {
            return 0;
        }
        fn report(context: ?*anyopaque, finding: *const Report) void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            if (finding.kind == .lock_held) _ = self.reports.fetchAdd(1, .acq_rel);
        }
    };
    var lock = Mutex.init("busy");
    var embedder: Embedder = .{};
    var watchdog: Watchdog = .{
        .config = .{
            .interval_ns = 2 * std.time.ns_per_ms,
            .threshold_ns = 10 * std.time.ns_per_s,
            .lock_hold_threshold_ns = 10 * std.time.ns_per_ms,
        },
        .context = &embedder,
        .report = Embedder.report,
        .progress = Embedder.progress,
        .lock = &lock,
    };
    try watchdog.start();
    // Always held when sampled, but released and retaken in between: a busy
    // lock, not a stuck holder.
    const until = futex.monotonicNanoseconds() + 60 * std.time.ns_per_ms;
    while (futex.monotonicNanoseconds() < until) {
        lock.lock();
        var pause = std.c.timespec{ .sec = 0, .nsec = 200 * std.time.ns_per_us };
        _ = std.c.nanosleep(&pause, null);
        lock.unlock();
    }
    watchdog.stop();
    try std.testing.expectEqual(@as(u32, 0), embedder.reports.load(.acquire));
}

test "the pulse runs on its interval with a rising sequence" {
    const Embedder = struct {
        pulses: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        last_sequence: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
        fn progress(_: ?*anyopaque) u64 {
            return 0;
        }
        fn report(_: ?*anyopaque, _: *const Report) void {}
        fn pulse(context: ?*anyopaque, snapshot: *const Pulse) void {
            const self: *@This() = @ptrCast(@alignCast(context.?));
            self.last_sequence.store(snapshot.sequence, .release);
            _ = self.pulses.fetchAdd(1, .acq_rel);
        }
    };
    var embedder: Embedder = .{};
    var watchdog: Watchdog = .{
        .config = .{
            .interval_ns = std.time.ns_per_s,
            .threshold_ns = 10 * std.time.ns_per_s,
            .pulse_interval_ns = 3 * std.time.ns_per_ms,
        },
        .context = &embedder,
        .report = Embedder.report,
        .progress = Embedder.progress,
        .pulse = Embedder.pulse,
    };
    try watchdog.start();
    const deadline = futex.monotonicNanoseconds() + 2 * std.time.ns_per_s;
    while (embedder.pulses.load(.acquire) < 3 and futex.monotonicNanoseconds() < deadline) {
        var pause = std.c.timespec{ .sec = 0, .nsec = std.time.ns_per_ms };
        _ = std.c.nanosleep(&pause, null);
    }
    watchdog.stop();
    try std.testing.expect(embedder.pulses.load(.acquire) >= 3);
    try std.testing.expectEqual(embedder.pulses.load(.acquire), embedder.last_sequence.load(.acquire));
}
