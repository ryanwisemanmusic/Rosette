//! A condition variable on one futex word.
//!
//! Waiters sample a sequence number under the mutex, release it and sleep
//! while the number is unchanged; signalling bumps the number and wakes.
//! A waiter count lets a signal with nobody waiting skip the system call,
//! which matters for Rosette's broadcast-heavy wakeup paths. Waits may
//! return spuriously, as every condition variable's may: re-check the
//! predicate under the mutex.

const std = @import("std");
const futex = @import("futex.zig");
const park = @import("park.zig");
const Mutex = @import("mutex.zig").Mutex;

pub const Condition = struct {
    sequence: futex.Word = futex.Word.init(0),
    waiters: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    label: [*:0]const u8 = "condition",

    pub fn init(label: [*:0]const u8) Condition {
        return .{ .label = label };
    }

    /// Release `mutex`, sleep until signalled, and take `mutex` again.
    pub fn wait(self: *Condition, mutex: *Mutex) void {
        self.timedWait(mutex, null);
    }

    /// As `wait`, but give up at the monotonic `deadline_ns`.
    pub fn timedWait(self: *Condition, mutex: *Mutex, deadline_ns: ?u64) void {
        const observed = self.sequence.load(.acquire);
        // Sequentially consistent with the signaller's increment and load:
        // either it sees this waiter and wakes, or the kernel's compare sees
        // the new sequence and does not sleep.
        _ = self.waiters.fetchAdd(1, .seq_cst);
        mutex.unlock();
        park.park(&self.sequence, observed, deadline_ns, self.label);
        _ = self.waiters.fetchSub(1, .monotonic);
        mutex.lock();
    }

    pub fn signal(self: *Condition) void {
        _ = self.sequence.fetchAdd(1, .seq_cst);
        if (self.waiters.load(.seq_cst) != 0) futex.wake(&self.sequence, .one);
    }

    pub fn broadcast(self: *Condition) void {
        _ = self.sequence.fetchAdd(1, .seq_cst);
        if (self.waiters.load(.seq_cst) != 0) futex.wake(&self.sequence, .all);
    }
};

test "a signalled waiter observes the predicate its signaller set" {
    const Shared = struct {
        mutex: Mutex = Mutex.init("condition test"),
        condition: Condition = Condition.init("ready"),
        ready: bool = false,
        observed: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

        fn waiter(shared: *@This()) void {
            shared.mutex.lock();
            while (!shared.ready) shared.condition.wait(&shared.mutex);
            shared.mutex.unlock();
            shared.observed.store(true, .release);
        }
    };
    var shared: Shared = .{};
    const thread = try std.Thread.spawn(.{}, Shared.waiter, .{&shared});
    var request = std.c.timespec{ .sec = 0, .nsec = 2 * std.time.ns_per_ms };
    _ = std.c.nanosleep(&request, null);
    shared.mutex.lock();
    shared.ready = true;
    shared.condition.broadcast();
    shared.mutex.unlock();
    thread.join();
    try std.testing.expect(shared.observed.load(.acquire));
}

test "a timed wait with nobody signalling returns at its deadline" {
    var mutex = Mutex.init("timed");
    var condition = Condition.init("never");
    mutex.lock();
    condition.timedWait(&mutex, futex.monotonicNanoseconds() + std.time.ns_per_ms);
    try std.testing.expect(mutex.heldByCurrentThread());
    mutex.unlock();
}
