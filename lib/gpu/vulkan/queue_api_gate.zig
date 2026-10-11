//! Serializes host operations that Vulkan requires to be externally
//! synchronized on queues. A waiter may drop Rosette's runtime mutex while it
//! sleeps; the active lease keeps native queue calls in one-at-a-time order.
const std = @import("std");
const transport_timing = @import("transport_timing.zig");

pub const Stats = struct {
    acquisitions: u64,
    contended: u64,
    waits: u64,
    wait_ns: u64,
    max_wait_ns: u64,
    wait_refusals: u64,
};

pub const Gate = struct {
    mutex: std.c.pthread_mutex_t = .{},
    available: std.c.pthread_cond_t = .{},
    held: bool = false,
    acquisitions: u64 = 0,
    contended: u64 = 0,
    waits: u64 = 0,
    wait_ns: u64 = 0,
    max_wait_ns: u64 = 0,
    wait_refusals: u64 = 0,

    pub const Lease = struct {
        gate: *Gate,
        active: bool = true,

        pub fn release(self: *Lease) void {
            if (!self.active) return;
            self.active = false;
            self.gate.release();
        }
    };

    /// Fast nonblocking admission for the common single queue thread.
    pub fn tryAcquire(self: *Gate) ?Lease {
        lock(&self.mutex);
        if (self.held) {
            self.contended +|= 1;
            unlock(&self.mutex);
            return null;
        }
        self.held = true;
        self.acquisitions +|= 1;
        unlock(&self.mutex);
        return .{ .gate = self };
    }

    /// Wait until the current queue operation releases its lease. Callers
    /// should use Rosetta's runtime-lock yield wrapper around this when the
    /// wait occurs inside guest dispatch.
    pub fn waitAcquire(self: *Gate) Lease {
        const started = transport_timing.nowNs();
        lock(&self.mutex);
        if (self.held) {
            self.waits +|= 1;
            while (self.held) wait(&self.available, &self.mutex);
        }
        self.held = true;
        self.acquisitions +|= 1;
        const elapsed = transport_timing.nowNs() -| started;
        if (elapsed != 0) {
            self.wait_ns +|= elapsed;
            self.max_wait_ns = @max(self.max_wait_ns, elapsed);
        }
        unlock(&self.mutex);
        return .{ .gate = self };
    }

    pub fn noteWaitRefusal(self: *Gate) void {
        lock(&self.mutex);
        self.wait_refusals +|= 1;
        unlock(&self.mutex);
    }

    pub fn stats(self: *const Gate) Stats {
        const mutex = @constCast(&self.mutex);
        lock(mutex);
        defer unlock(mutex);
        return .{
            .acquisitions = self.acquisitions,
            .contended = self.contended,
            .waits = self.waits,
            .wait_ns = self.wait_ns,
            .max_wait_ns = self.max_wait_ns,
            .wait_refusals = self.wait_refusals,
        };
    }

    fn release(self: *Gate) void {
        lock(&self.mutex);
        if (!self.held) unreachable;
        self.held = false;
        broadcast(&self.available);
        unlock(&self.mutex);
    }
};

fn lock(mutex: *std.c.pthread_mutex_t) void {
    if (std.c.pthread_mutex_lock(mutex) != .SUCCESS) unreachable;
}

fn unlock(mutex: *std.c.pthread_mutex_t) void {
    if (std.c.pthread_mutex_unlock(mutex) != .SUCCESS) unreachable;
}

fn wait(condition: *std.c.pthread_cond_t, mutex: *std.c.pthread_mutex_t) void {
    if (std.c.pthread_cond_wait(condition, mutex) != .SUCCESS) unreachable;
}

fn broadcast(condition: *std.c.pthread_cond_t) void {
    if (std.c.pthread_cond_broadcast(condition) != .SUCCESS) unreachable;
}

test "Vulkan queue gate admits one operation and releases it exactly once" {
    var gate: Gate = .{};
    var first = gate.tryAcquire().?;
    try std.testing.expect(gate.tryAcquire() == null);
    first.release();
    var second = gate.tryAcquire().?;
    second.release();

    const stats = gate.stats();
    try std.testing.expectEqual(@as(u64, 2), stats.acquisitions);
    try std.testing.expectEqual(@as(u64, 1), stats.contended);
}

test "Vulkan queue gate wakes a blocked queue operation after release" {
    const Waiter = struct {
        gate: *Gate,
        acquired: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

        fn run(self: *@This()) void {
            var lease = self.gate.waitAcquire();
            self.acquired.store(true, .release);
            lease.release();
        }
    };

    var gate: Gate = .{};
    var first = gate.tryAcquire().?;
    var waiter = Waiter{ .gate = &gate };
    const thread = try std.Thread.spawn(.{}, Waiter.run, .{&waiter});
    while (gate.stats().waits == 0) std.Thread.yield() catch std.atomic.spinLoopHint();
    try std.testing.expect(!waiter.acquired.load(.acquire));
    first.release();
    thread.join();
    try std.testing.expect(waiter.acquired.load(.acquire));
    try std.testing.expectEqual(@as(u64, 1), gate.stats().waits);
}
