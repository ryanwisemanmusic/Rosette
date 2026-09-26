//! An epoch that threads sleep on until it moves.
//!
//! `notify` bumps the epoch; `waitChange` sleeps until the epoch differs from
//! the value the caller sampled before checking its own predicate. Sampling
//! first is what makes the pattern lose no wakeup: a notify that races the
//! predicate check still moves the epoch past the sampled value.
//!
//! This replaces the PE executor's `WakeHub`, whose waiters polled the epoch
//! in one-millisecond sleeps. Here a waiter sleeps in the kernel until the
//! notify, and a notify with nobody asleep is one atomic increment.

const std = @import("std");
const futex = @import("futex.zig");
const park = @import("park.zig");

pub const EpochEvent = struct {
    epoch: futex.Word = futex.Word.init(0),
    waiters: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),
    notifies: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    wakes: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    label: [*:0]const u8 = "event",

    pub fn init(label: [*:0]const u8) EpochEvent {
        return .{ .label = label };
    }

    pub fn current(self: *const EpochEvent) u32 {
        return self.epoch.load(.acquire);
    }

    /// Move the epoch and wake every sleeper.
    pub fn notify(self: *EpochEvent) void {
        _ = self.epoch.fetchAdd(1, .seq_cst);
        _ = self.notifies.fetchAdd(1, .monotonic);
        if (self.waiters.load(.seq_cst) != 0) {
            _ = self.wakes.fetchAdd(1, .monotonic);
            futex.wake(&self.epoch, .all);
        }
    }

    /// Sleep until the epoch differs from `observed`, or until the monotonic
    /// `deadline_ns` passes. True when the epoch moved.
    pub fn waitChange(self: *EpochEvent, observed: u32, deadline_ns: ?u64) bool {
        _ = self.waiters.fetchAdd(1, .seq_cst);
        defer _ = self.waiters.fetchSub(1, .monotonic);
        while (self.epoch.load(.seq_cst) == observed) {
            if (deadline_ns) |deadline| {
                if (futex.monotonicNanoseconds() >= deadline) return false;
            }
            park.park(&self.epoch, observed, deadline_ns, self.label);
        }
        return true;
    }
};

test "a notify before the wait is not lost" {
    var event = EpochEvent.init("early");
    const observed = event.current();
    event.notify();
    try std.testing.expect(event.waitChange(observed, null));
}

test "a waiter sleeps until notified from another thread" {
    const Shared = struct {
        event: EpochEvent = EpochEvent.init("late"),
        flag: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

        fn waiter(shared: *@This()) void {
            while (true) {
                const observed = shared.event.current();
                if (shared.flag.load(.acquire)) return;
                _ = shared.event.waitChange(observed, null);
            }
        }
    };
    var shared: Shared = .{};
    const thread = try std.Thread.spawn(.{}, Shared.waiter, .{&shared});
    var request = std.c.timespec{ .sec = 0, .nsec = 2 * std.time.ns_per_ms };
    _ = std.c.nanosleep(&request, null);
    shared.flag.store(true, .release);
    shared.event.notify();
    thread.join();
}

test "a wait with a passed deadline reports no change" {
    var event = EpochEvent.init("deadline");
    try std.testing.expect(!event.waitChange(event.current(), futex.monotonicNanoseconds()));
}
