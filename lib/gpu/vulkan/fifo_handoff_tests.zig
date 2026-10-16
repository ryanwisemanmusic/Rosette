//! Spin-then-park FIFO handoff: order, wakeups, drains and shutdown.
//! CPU stub callbacks only; nothing here dispatches GPU work.
const std = @import("std");
const abi = @import("abi.zig");
const fifo = @import("async_command_worker.zig");
const handoff = @import("fifo_handoff.zig");

const Order = struct {
    next: u64 = 0,
    errors: u64 = 0,
    executed: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

    fn context(buffer: abi.CommandBuffer) *Order {
        return @ptrCast(@alignCast(buffer.?));
    }
    fn draw(buffer: abi.CommandBuffer, low: u32, high: u32, _: u32, _: u32) callconv(.c) void {
        const self = context(buffer);
        const value = @as(u64, high) << 32 | low;
        if (value != self.next) self.errors += 1;
        self.next = value + 1;
        _ = self.executed.fetchAdd(1, .release);
    }
};

fn job(order: *Order, value: u64) fifo.Job {
    return .{ .draw = .{
        .function = Order.draw,
        .command_buffer = @ptrCast(order),
        .vertex_count = @truncate(value),
        .instance_count = @truncate(value >> 32),
        .first_vertex = 0,
        .first_instance = 0,
    } };
}

/// The production overflow route: drain, then call synchronously.
fn submit(worker: *fifo.Worker, order: *Order, value: u64) void {
    const next = job(order, value);
    if (worker.trySubmit(next) == .queued) return;
    worker.drain();
    Order.draw(@ptrCast(order), @truncate(value), @truncate(value >> 32), 0, 0);
}

fn busy(ns: u64) void {
    const end = handoff.nowNs() + ns;
    while (handoff.nowNs() < end) std.atomic.spinLoopHint();
}

const Producer = struct {
    worker: *fifo.Worker,
    order: *Order,
    gate: *std.atomic.Mutex,
    counter: *u64,
    total: u64,
    seed: u64,

    fn run(self: *Producer) void {
        var random = std.Random.DefaultPrng.init(self.seed);
        while (true) {
            // The forwarder's callers are serialized by the runtime lock but
            // may be different host threads; the gate plays that role.
            while (!self.gate.tryLock()) std.atomic.spinLoopHint();
            defer self.gate.unlock();
            if (self.counter.* == self.total) return;
            const burst = random.random().intRangeAtMost(u64, 1, 24);
            for (0..burst) |_| {
                if (self.counter.* == self.total) break;
                submit(self.worker, self.order, self.counter.*);
                self.counter.* += 1;
                if (random.random().uintLessThan(u32, 8) == 0) busy(random.random().uintLessThan(u64, 3_000));
                if (random.random().uintLessThan(u32, 20) == 0) self.worker.drain();
            }
        }
    }
};

fn stress(total: u64) !fifo.Stats {
    var order = Order{};
    var worker = fifo.Worker{};
    try worker.start();
    defer worker.deinit();
    var gate: std.atomic.Mutex = .unlocked;
    var counter: u64 = 0;
    var producers: [2]Producer = undefined;
    var threads: [2]std.Thread = undefined;
    for (&producers, &threads, 0..) |*producer, *thread, index| {
        producer.* = .{ .worker = &worker, .order = &order, .gate = &gate, .counter = &counter, .total = total, .seed = 0x5eed + index };
        thread.* = try std.Thread.spawn(.{}, Producer.run, .{producer});
    }
    for (threads) |thread| thread.join();
    worker.drain();
    try std.testing.expectEqual(total, order.next);
    try std.testing.expectEqual(@as(u64, 0), order.errors);
    return worker.stats();
}

test "FIFO handoff keeps exact order across serialized producer threads, gaps and barriers" {
    const saved = handoff.enabled;
    defer handoff.enabled = saved;
    for ([_]bool{ true, false }) |enabled| {
        handoff.enabled = enabled;
        const stats = try stress(60_000);
        try std.testing.expectEqual(stats.submitted, stats.completed);
        if (!enabled) try std.testing.expectEqual(@as(u64, 0), stats.spin_pickups + stats.drain_spin_hits);
    }
}

test "FIFO handoff parks an idle worker and wakes it for the next command" {
    const saved = handoff.enabled;
    const saved_spin = handoff.worker_spin_ns;
    defer handoff.enabled = saved;
    defer handoff.worker_spin_ns = saved_spin;
    handoff.enabled = true;
    handoff.worker_spin_ns = 20 * std.time.ns_per_us;
    var order = Order{};
    var worker = fifo.Worker{};
    try worker.start();
    defer worker.deinit();
    for (0..50) |round| {
        // Wait until the worker has gone to sleep after its polling budget
        // (a loaded host can delay that well past the budget), then prove
        // a single submission still wakes it (no lost wakeup).
        const park_deadline = handoff.nowNs() + 2 * std.time.ns_per_s;
        while (worker.stats().parks <= round and handoff.nowNs() < park_deadline) busy(50 * std.time.ns_per_us);
        try std.testing.expect(worker.stats().parks > round);
        try std.testing.expect(worker.trySubmit(job(&order, round)) == .queued);
        const deadline = handoff.nowNs() + 2 * std.time.ns_per_s;
        while (order.executed.load(.acquire) != round + 1 and handoff.nowNs() < deadline) std.atomic.spinLoopHint();
        try std.testing.expectEqual(@as(u64, round + 1), order.executed.load(.acquire));
    }
    const stats = worker.stats();
    try std.testing.expect(stats.parks >= 50);
    try std.testing.expect(stats.work_signals >= 1);
    try std.testing.expectEqual(@as(u64, 0), order.errors);
}

test "FIFO handoff satisfies a barrier by polling while the worker is busy" {
    const saved = handoff.enabled;
    defer handoff.enabled = saved;
    handoff.enabled = true;
    var order = Order{};
    var worker = fifo.Worker{};
    try worker.start();
    defer worker.deinit();
    for (0..2000) |value| {
        try std.testing.expect(worker.trySubmit(job(&order, value)) == .queued);
        if (value % 4 == 3) worker.drain();
        try std.testing.expect(value % 4 != 3 or order.executed.load(.acquire) == value + 1);
    }
    worker.drain();
    const stats = worker.stats();
    try std.testing.expectEqual(@as(u64, 2000), stats.completed);
    try std.testing.expect(stats.drain_spin_hits > 0);
    try std.testing.expectEqual(@as(u64, 0), order.errors);
}

test "FIFO handoff shutdown interrupts the idle poll promptly" {
    const saved = handoff.enabled;
    const saved_spin = handoff.worker_spin_ns;
    defer handoff.enabled = saved;
    defer handoff.worker_spin_ns = saved_spin;
    handoff.enabled = true;
    handoff.worker_spin_ns = 10 * std.time.ns_per_s;
    var order = Order{};
    var worker = fifo.Worker{};
    try worker.start();
    try std.testing.expect(worker.trySubmit(job(&order, 0)) == .queued);
    worker.drain();
    const started = handoff.nowNs();
    worker.deinit();
    try std.testing.expect(handoff.nowNs() - started < std.time.ns_per_s);
    try std.testing.expectEqual(@as(u64, 1), order.next);
}
