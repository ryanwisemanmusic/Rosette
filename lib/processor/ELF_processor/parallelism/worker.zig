//! Host-thread lifetime and wake signaling for PE guest execution workers.
//!
//! The worker owns no guest state itself. The embedding Windows thread slot
//! is stable for the lifetime of its callback and supplies the guest context.
//! Slot notifications keep independent parked threads from waking as a herd.
//! Callers must stop and join every worker before freeing that state or its
//! guest address space.

const std = @import("std");
const concurrency = @import("concurrency");

/// Owner-side and per-worker epoch events for PE guest execution. The owner
/// event preserves scheduler/owner waits; worker events target only the slot
/// made runnable. A mask coalesces repeated transitions to the same slot
/// until the runtime lock is released.
pub const WakeHub = struct {
    /// Owner-side waits listen to this event. Guest workers use their own
    /// slot event below so waking one runnable guest does not wake every
    /// blocked worker on the process-wide hub.
    event: concurrency.EpochEvent = concurrency.EpochEvent.init("guest worker owner wake hub"),
    worker_events: [worker_capacity]concurrency.EpochEvent = initWorkerEvents(),
    /// Waits that ended on the safety-net timeout rather than a notify.
    timeouts: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    /// Waits that ended at the guest wait's own deadline (a `Sleep`, a timed
    /// wait): the expected end of a timed park, not a missed notify. These
    /// used to be counted with the safety-net timeouts, which made a thread
    /// sleeping in a loop look like a wake that kept failing.
    deadline_expiries: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    /// Timeouts after which the worker's thread was found runnable: a state
    /// transition that should have notified and did not. Must read zero.
    lost_wakeups: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

    pub const worker_capacity = 64;

    fn initWorkerEvents() [worker_capacity]concurrency.EpochEvent {
        var events: [worker_capacity]concurrency.EpochEvent = undefined;
        for (&events) |*event| event.* = concurrency.EpochEvent.init("guest worker slot wake");
        return events;
    }

    pub fn notify(self: *WakeHub) void {
        self.event.notify();
    }

    pub fn epoch(self: *const WakeHub) u32 {
        return self.event.current();
    }

    pub fn workerEpoch(self: *const WakeHub, slot: usize) u32 {
        std.debug.assert(slot < worker_capacity);
        return self.worker_events[slot].current();
    }

    pub fn notifyWorker(self: *WakeHub, slot: usize) void {
        std.debug.assert(slot < worker_capacity);
        self.worker_events[slot].notify();
    }

    pub fn notifyAllWorkers(self: *WakeHub) void {
        for (&self.worker_events) |*event| event.notify();
    }

    /// Notify only slots made runnable in one locked runtime transition.
    /// `worker_count` bounds the mask to the live guest-thread table; high
    /// bits are ignored so a stale or malformed slot cannot signal another
    /// event in the hub.
    pub fn notifyMask(self: *WakeHub, mask: u64, worker_count: usize) void {
        const count = @min(worker_count, worker_capacity);
        const valid_mask = if (count == worker_capacity)
            std.math.maxInt(u64)
        else if (count == 0)
            0
        else
            (@as(u64, 1) << @intCast(count)) - 1;
        var pending = mask & valid_mask;
        while (pending != 0) : (pending &= pending - 1) {
            self.notifyWorker(@intCast(@ctz(pending)));
        }
    }

    pub fn workerNotificationCounts(self: *const WakeHub) struct { notifications: u64, wakes: u64 } {
        var notifications: u64 = 0;
        var wakes: u64 = 0;
        for (&self.worker_events) |*event| {
            notifications +|= event.notifies.load(.monotonic);
            wakes +|= event.wakes.load(.monotonic);
        }
        return .{ .notifications = notifications, .wakes = wakes };
    }
};

/// A parked worker re-checks its thread's state at least this often, so a
/// transition that forgot to notify costs latency, never a hang. Each such
/// recovery is counted (`WakeHub.lost_wakeups`).
pub const wake_safety_net_ns: u64 = 100 * std.time.ns_per_ms;

pub const WaitOutcome = enum {
    changed,
    /// The safety net ran out with nothing notified.
    timed_out,
    /// The caller's own deadline came first.
    deadline_reached,
    stopping,
};

pub const Worker = struct {
    thread: ?std.Thread = null,
    stop_requested: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    wake_hub: ?*WakeHub = null,
    callback: ?*const fn (*anyopaque, *Worker) void = null,
    context: ?*anyopaque = null,
    slot: usize = 0,

    pub fn start(
        self: *Worker,
        context: *anyopaque,
        slot: usize,
        wake_hub: *WakeHub,
        callback: *const fn (*anyopaque, *Worker) void,
    ) !void {
        if (self.thread != null) return error.WorkerAlreadyStarted;
        if (slot >= WakeHub.worker_capacity) return error.WorkerSlotOutOfRange;
        self.stop_requested.store(false, .release);
        self.context = context;
        self.slot = slot;
        self.wake_hub = wake_hub;
        self.callback = callback;
        self.thread = try std.Thread.spawn(.{}, run, .{self});
    }

    pub fn isStarted(self: *const Worker) bool {
        return self.thread != null;
    }

    pub fn shouldStop(self: *const Worker) bool {
        return self.stop_requested.load(.acquire);
    }

    /// Publish a lifecycle change (wake, shutdown, or scheduler event).
    pub fn notify(self: *Worker) void {
        if (self.wake_hub) |hub| hub.notifyWorker(self.slot);
    }

    pub fn epoch(self: *const Worker) u32 {
        const hub = self.wake_hub orelse return 0;
        return hub.workerEpoch(self.slot);
    }

    /// Wait only while the observed epoch is still current. Capturing the
    /// epoch before checking the guest wait predicate prevents a wake that
    /// races the predicate check from being lost. The thread sleeps in the
    /// kernel until a notify; it used to poll the epoch every millisecond,
    /// which with dozens of parked guest threads was thousands of wakeups a
    /// second that each did a stop-the-world store-buffer drain.
    ///
    /// `deadline_ns` (monotonic) ends the sleep early, for a guest wait with
    /// a timeout: the worker then expires its own wait instead of waiting for
    /// some other thread's sweep. Without one the sleep lasts until a notify,
    /// re-checked at the safety-net interval.
    pub fn waitForChange(self: *Worker, observed: u32, deadline_ns: ?u64) WaitOutcome {
        const hub = self.wake_hub orelse return .stopping;
        if (self.shouldStop()) return .stopping;
        if (hub.workerEpoch(self.slot) != observed) return .changed;
        const safety_net = concurrency.monotonicNanoseconds() +| wake_safety_net_ns;
        const own_deadline_first = if (deadline_ns) |requested| requested <= safety_net else false;
        const deadline = if (deadline_ns) |requested| @min(requested, safety_net) else safety_net;
        if (hub.worker_events[self.slot].waitChange(observed, deadline)) return .changed;
        if (self.shouldStop()) return .stopping;
        if (own_deadline_first) {
            _ = hub.deadline_expiries.fetchAdd(1, .monotonic);
            return .deadline_reached;
        }
        _ = hub.timeouts.fetchAdd(1, .monotonic);
        return .timed_out;
    }

    /// Host-only bounded idle backoff. Does not expire or count guest waits.
    /// The epoch is captured before the preceding guest poll, so a racing
    /// notification returns immediately. Unnotified memory polls retry at
    /// the deadline; shutdown always notifies this event.
    pub fn waitForHostBackoff(self: *Worker, observed: u32, deadline: u64) WaitOutcome {
        const hub = self.wake_hub orelse return .stopping;
        if (self.shouldStop()) return .stopping;
        if (hub.worker_events[self.slot].waitChange(observed, deadline)) return .changed;
        return if (self.shouldStop()) .stopping else .deadline_reached;
    }

    /// The caller found its thread runnable after a `.timed_out` wait.
    pub fn noteLostWakeup(self: *Worker) void {
        if (self.wake_hub) |hub| _ = hub.lost_wakeups.fetchAdd(1, .monotonic);
    }

    pub fn requestStop(self: *Worker) void {
        self.stop_requested.store(true, .release);
        self.notify();
    }

    /// Join consumes the host handle exactly once. A stopped callback must
    /// have returned before its embedded guest context can be recycled.
    pub fn join(self: *Worker) void {
        if (self.thread) |thread| {
            thread.join();
            self.thread = null;
        }
        self.context = null;
        self.callback = null;
        self.wake_hub = null;
    }

    fn run(self: *Worker) void {
        const context = self.context orelse return;
        const callback = self.callback orelse return;
        callback(context, self);
    }
};

test "a worker receives lifecycle notifications and joins once" {
    const Shared = struct {
        entered: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        returned: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

        fn callback(raw: *anyopaque, worker: *Worker) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            self.entered.store(true, .release);
            while (!worker.shouldStop()) {
                const observed = worker.epoch();
                _ = worker.waitForChange(observed, null);
            }
            self.returned.store(true, .release);
        }
    };

    var shared: Shared = .{};
    var worker: Worker = .{};
    var hub: WakeHub = .{};
    try worker.start(@ptrCast(&shared), 3, &hub, Shared.callback);
    while (!shared.entered.load(.acquire)) std.Thread.yield() catch std.atomic.spinLoopHint();
    worker.requestStop();
    worker.join();
    try std.testing.expect(shared.returned.load(.acquire));
    try std.testing.expect(!worker.isStarted());
}

test "a second start is rejected until the previous worker has joined" {
    var worker: Worker = .{};
    var hub: WakeHub = .{};
    const callback = struct {
        fn run(_: *anyopaque, context: *Worker) void {
            while (!context.shouldStop()) {
                const observed = context.epoch();
                _ = context.waitForChange(observed, null);
            }
        }
    }.run;
    var value: u8 = 0;
    try worker.start(@ptrCast(&value), 0, &hub, callback);
    try std.testing.expectError(error.WorkerAlreadyStarted, worker.start(@ptrCast(&value), 0, &hub, callback));
    worker.requestStop();
    worker.join();
    try worker.start(@ptrCast(&value), 0, &hub, callback);
    worker.requestStop();
    worker.join();
}

test "targeted worker notification does not wake unrelated parked guest slots" {
    const Shared = struct {
        entered: [2]std.atomic.Value(bool) = .{
            std.atomic.Value(bool).init(false),
            std.atomic.Value(bool).init(false),
        },

        fn callback(raw: *anyopaque, worker: *Worker) void {
            const self: *@This() = @ptrCast(@alignCast(raw));
            while (!worker.shouldStop()) {
                const observed = worker.epoch();
                self.entered[worker.slot].store(true, .release);
                _ = worker.waitForChange(observed, null);
            }
        }
    };

    var shared: Shared = .{};
    var hub: WakeHub = .{};
    var workers = [_]Worker{ .{}, .{} };
    try workers[0].start(@ptrCast(&shared), 0, &hub, Shared.callback);
    try workers[1].start(@ptrCast(&shared), 1, &hub, Shared.callback);
    defer {
        workers[0].requestStop();
        workers[1].requestStop();
        workers[0].join();
        workers[1].join();
    }

    const ready_deadline = concurrency.monotonicNanoseconds() + std.time.ns_per_s;
    while (hub.worker_events[0].waiters.load(.acquire) == 0 or
        hub.worker_events[1].waiters.load(.acquire) == 0)
    {
        if (concurrency.monotonicNanoseconds() >= ready_deadline) break;
        std.Thread.yield() catch std.atomic.spinLoopHint();
    }
    try std.testing.expect(shared.entered[0].load(.acquire));
    try std.testing.expect(shared.entered[1].load(.acquire));
    try std.testing.expectEqual(@as(u32, 1), hub.worker_events[0].waiters.load(.acquire));
    try std.testing.expectEqual(@as(u32, 1), hub.worker_events[1].waiters.load(.acquire));

    workers[0].notify();
    const wake_deadline = concurrency.monotonicNanoseconds() + std.time.ns_per_s;
    while (hub.worker_events[0].wakes.load(.acquire) == 0 and
        concurrency.monotonicNanoseconds() < wake_deadline)
    {
        std.Thread.yield() catch std.atomic.spinLoopHint();
    }
    try std.testing.expectEqual(@as(u64, 1), hub.worker_events[0].wakes.load(.acquire));
    try std.testing.expectEqual(@as(u64, 0), hub.worker_events[1].wakes.load(.acquire));
    try std.testing.expectEqual(@as(u64, 1), hub.worker_events[0].notifies.load(.acquire));
    try std.testing.expectEqual(@as(u64, 0), hub.worker_events[1].notifies.load(.acquire));
}

test "worker notification mask coalesces and bounds runnable slots" {
    var hub: WakeHub = .{};
    hub.notifyMask(0b1010_0101, 6);
    const counts = hub.workerNotificationCounts();
    try std.testing.expectEqual(@as(u64, 3), counts.notifications);
    try std.testing.expectEqual(@as(u64, 0), counts.wakes);
    try std.testing.expectEqual(@as(u64, 1), hub.worker_events[0].notifies.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 0), hub.worker_events[1].notifies.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 1), hub.worker_events[2].notifies.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 0), hub.worker_events[3].notifies.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 0), hub.worker_events[4].notifies.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 1), hub.worker_events[5].notifies.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 0), hub.worker_events[6].notifies.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 0), hub.worker_events[7].notifies.load(.monotonic));
}

test "a wait that ends at its own deadline is not a safety-net timeout" {
    var worker: Worker = .{};
    var hub: WakeHub = .{};
    worker.wake_hub = &hub;
    const observed = worker.epoch();
    const outcome = worker.waitForChange(observed, concurrency.monotonicNanoseconds() + 2 * std.time.ns_per_ms);
    try std.testing.expectEqual(WaitOutcome.deadline_reached, outcome);
    try std.testing.expectEqual(@as(u64, 1), hub.deadline_expiries.load(.acquire));
    try std.testing.expectEqual(@as(u64, 0), hub.timeouts.load(.acquire));
    worker.wake_hub = null;
}
