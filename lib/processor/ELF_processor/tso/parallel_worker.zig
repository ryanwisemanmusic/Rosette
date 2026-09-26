//! Host-thread lifetime and wake signaling for PE guest execution workers.
//!
//! The worker owns no guest state itself. The embedding Windows thread slot
//! is stable for the lifetime of its callback and supplies the guest context.
//! Callers must stop and join every worker before freeing that state or its
//! guest address space.

const std = @import("std");
const concurrency = @import("concurrency");

/// One event shared by every guest worker in a PE process. Runtime
/// transitions notify it once, so a blocking API need not walk the whole
/// guest-thread table to wake parked host workers. A notify with nobody
/// asleep is one atomic increment; a sleeper is woken by the kernel.
pub const WakeHub = struct {
    event: concurrency.EpochEvent = concurrency.EpochEvent.init("guest worker wake hub"),
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

    pub fn notify(self: *WakeHub) void {
        self.event.notify();
    }

    pub fn epoch(self: *const WakeHub) u32 {
        return self.event.current();
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
        if (self.wake_hub) |hub| hub.notify();
    }

    pub fn epoch(self: *const Worker) u32 {
        const hub = self.wake_hub orelse return 0;
        return hub.epoch();
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
        if (hub.epoch() != observed) return .changed;
        const safety_net = concurrency.monotonicNanoseconds() +| wake_safety_net_ns;
        const own_deadline_first = if (deadline_ns) |requested| requested <= safety_net else false;
        const deadline = if (deadline_ns) |requested| @min(requested, safety_net) else safety_net;
        if (hub.event.waitChange(observed, deadline)) return .changed;
        if (self.shouldStop()) return .stopping;
        if (own_deadline_first) {
            _ = hub.deadline_expiries.fetchAdd(1, .monotonic);
            return .deadline_reached;
        }
        _ = hub.timeouts.fetchAdd(1, .monotonic);
        return .timed_out;
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

test "a wait that ends at its own deadline is not a safety-net timeout" {
    var worker: Worker = .{};
    var hub: WakeHub = .{};
    worker.wake_hub = &hub;
    const observed = hub.epoch();
    const outcome = worker.waitForChange(observed, concurrency.monotonicNanoseconds() + 2 * std.time.ns_per_ms);
    try std.testing.expectEqual(WaitOutcome.deadline_reached, outcome);
    try std.testing.expectEqual(@as(u64, 1), hub.deadline_expiries.load(.acquire));
    try std.testing.expectEqual(@as(u64, 0), hub.timeouts.load(.acquire));
    worker.wake_hub = null;
}
