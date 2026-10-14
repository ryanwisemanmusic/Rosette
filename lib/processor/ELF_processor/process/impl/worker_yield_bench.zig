//! CPU-only production scheduling checks. No emulator or GPU work.
const std = @import("std");
const clock = @import("concurrency");
const scheduling = @import("worker_yield.zig");
const workers = @import("parallelism").worker;
const atomic = std.atomic.Value;
const Regs = struct {
    rax: u64 = 0,
    rcx: u64 = 0,
    rdx: u64 = 0,
    mxcsr: u64 = 0x1F80,
    rip: u64 = 0x1000,
    rsp: u64 = 0x2000,
    rbx: u64 = 0,
    rbp: u64 = 0,
    rsi: u64 = 0,
    rdi: u64 = 0,
    r8: u64 = 0,
    r9: u64 = 0,
    r10: u64 = 0,
    r11: u64 = 0,
    r12: u64 = 0,
    r13: u64 = 0,
    r14: u64 = 0,
    r15: u64 = 0,
    rflags: u64 = 2,
};
const Context = struct {
    regs: Regs = .{},
    windows_slice_nt_zero_yield: bool = true,
    windows_slice_pause_yield: bool = false,
    windows_guest_handoff_requested: bool = false,
    windows_guest_slice_yield_requested: bool = true,
};
const Thread = struct { pause_host_yields: u64 = 0 };
const State = struct {
    windows_idle_yield: scheduling.Ledger = .{},
    frame_cost: struct { swaps: u64 = 0 } = .{},
};
fn cpuNanoseconds() u64 {
    var time: std.c.timespec = undefined;
    std.debug.assert(std.c.clock_gettime(.THREAD_CPUTIME_ID, &time) == 0);
    return @as(u64, @intCast(time.sec)) * std.time.ns_per_s + @as(u64, @intCast(time.nsec));
}
fn sleep(ns: u64) void {
    var time: std.c.timespec = .{ .sec = @intCast(ns / std.time.ns_per_s), .nsec = @intCast(ns % std.time.ns_per_s) };
    _ = std.c.nanosleep(&time, null);
}
const Poller = struct {
    state: State = .{},
    thread: Thread = .{},
    context: Context = .{},
    route: scheduling.Route = .{},
    worker: workers.Worker = .{},
    ready: atomic(bool) = .init(false),
    sent: atomic(u64) = .init(0),
    received: atomic(u64) = .init(0),
    checksum: u64 = 0,
    cpu_ns: u64 = 0,
    iterations: u64 = 0,
    productive: bool = false,
    fn run(raw: *anyopaque, worker: *workers.Worker) void {
        const self: *@This() = @ptrCast(@alignCast(raw));
        self.route.setLabel("XThread0022");
        const started = cpuNanoseconds();
        self.ready.store(true, .release);
        while (!worker.shouldStop()) {
            const next = self.sent.load(.acquire);
            if (next != self.received.load(.monotonic)) {
                self.checksum +%= next *% 0x9e3779b97f4a7c15;
                self.context.regs.r15 = next;
                self.received.store(next, .release);
            }
            if (self.productive) self.context.regs.r12 +%= 1;
            self.context.windows_slice_nt_zero_yield = true;
            self.context.windows_guest_slice_yield_requested = true;
            scheduling.handle(&self.state, &self.thread, &self.context, worker, &self.route, self.iterations * 10, true);
            self.iterations += 1;
        }
        self.cpu_ns = cpuNanoseconds() - started;
        self.route.flush(&self.state.windows_idle_yield);
    }
};
test "worker yield backoff uses targeted notification and preserves guest wait metrics" {
    var hub: workers.WakeHub = .{};
    var worker: workers.Worker = .{ .wake_hub = &hub, .slot = 2 };
    var route: scheduling.Route = .{};
    route.epoch = worker.epoch();
    worker.notify(); // Notification between guest predicate read and host wait.
    route.park(&worker, 500000);
    try std.testing.expectEqual(@as(u64, 1), route.counters.notified);
    try std.testing.expectEqual(@as(u64, 0), hub.deadline_expiries.load(.acquire));
    route.epoch = worker.epoch();
    route.park(&worker, 10000);
    try std.testing.expectEqual(@as(u64, 0), hub.timeouts.load(.acquire));
    try std.testing.expectEqual(@as(u64, 0), hub.deadline_expiries.load(.acquire));
    worker.requestStop();
    route.park(&worker, 500000);
    try std.testing.expectEqual(@as(u64, 1), route.counters.stopped);
}
test "worker yield backoff only handles explicit marker and retains PAUSE counts" {
    var state: State = .{};
    var thread: Thread = .{};
    var context: Context = .{ .windows_slice_pause_yield = true };
    var hub: workers.WakeHub = .{};
    var worker: workers.Worker = .{ .wake_hub = &hub };
    var route: scheduling.Route = .{};
    route.setLabel("XThread0022");
    scheduling.handle(&state, &thread, &context, &worker, &route, 10, true);
    try std.testing.expectEqual(@as(u64, 1), thread.pause_host_yields);
    try std.testing.expectEqual(@as(u64, 0), route.counters.explicit);
    try std.testing.expect(!context.windows_slice_nt_zero_yield);
    try std.testing.expect(!context.windows_guest_slice_yield_requested);
    context.windows_slice_nt_zero_yield = true;
    context.windows_guest_handoff_requested = true;
    scheduling.handle(&state, &thread, &context, &worker, &route, 20, true);
    try std.testing.expectEqual(@as(u64, 0), route.counters.explicit);
    try std.testing.expect(!context.windows_guest_handoff_requested);
}
const Mode = enum { idle, raw, notified, short, productive };
fn sample(mode: Mode, enabled: bool, pair: usize) !void {
    var pollers: [4]Poller = @splat(.{});
    var hub: workers.WakeHub = .{};
    var started: usize = 0;
    defer for (pollers[0..started]) |*p| {
        p.worker.requestStop();
        p.worker.join();
    };
    for (&pollers, 0..) |*p, slot| {
        p.state.windows_idle_yield.enabled = enabled;
        p.productive = mode == .productive;
        try p.worker.start(p, slot, &hub, Poller.run);
        started += 1;
    }
    for (&pollers) |*p| while (!p.ready.load(.acquire)) {
        std.Thread.yield() catch {};
    };
    const start = clock.monotonicNanoseconds();
    var latency: [80]u64 = @splat(0);
    var count: usize = 0;
    if (mode == .idle or mode == .productive) sleep(120 * std.time.ns_per_ms) else {
        for (1..21) |sequence| {
            sleep(if (mode == .short) 200000 else 5 * std.time.ns_per_ms);
            var stamps: [4]u64 = undefined;
            for (&pollers, 0..) |*p, i| {
                stamps[i] = clock.monotonicNanoseconds();
                p.sent.store(sequence, .release);
                if (mode == .notified) p.worker.notify();
            }
            for (&pollers, 0..) |*p, i| {
                while (p.received.load(.acquire) != sequence) {
                    if (clock.monotonicNanoseconds() - stamps[i] > std.time.ns_per_s) return error.HandoffStalled;
                    std.Thread.yield() catch {};
                }
                latency[count] = clock.monotonicNanoseconds() - stamps[i];
                count += 1;
            }
        }
    }
    for (&pollers) |*p| p.worker.requestStop();
    for (&pollers) |*p| p.worker.join();
    started = 0;
    const elapsed = clock.monotonicNanoseconds() - start;
    var cpu: u64 = 0;
    var parks: u64 = 0;
    var iterations: u64 = 0;
    for (&pollers) |*p| {
        cpu += p.cpu_ns;
        iterations += p.iterations;
        parks += p.state.windows_idle_yield.values[3].load(.acquire);
        var expected: u64 = 0;
        if (count != 0) for (1..21) |seq| {
            expected +%= seq *% 0x9e3779b97f4a7c15;
        };
        try std.testing.expectEqual(expected, p.checksum);
        if (mode == .short or mode == .productive) try std.testing.expectEqual(@as(u64, 0), p.state.windows_idle_yield.values[3].load(.acquire));
    }
    std.mem.sort(u64, latency[0..count], {}, std.sort.asc(u64));
    std.debug.print("WORKER_PRESSURE pair={d} mode={s} enabled={} cpu_ns={d} elapsed_ns={d} iterations={d} parks={d} checked={d} p95_ns={d} max_ns={d}\n", .{ pair, @tagName(mode), enabled, cpu, elapsed, iterations, parks, count, if (count == 0) 0 else latency[count * 95 / 100], if (count == 0) 0 else latency[count - 1] });
}
test "worker yield backoff production CPU benchmark (ROSETTE_WORKER_PRESSURE_BENCH=1)" {
    if (std.c.getenv("ROSETTE_WORKER_PRESSURE_BENCH") == null) return error.SkipZigTest;
    for (0..7) |pair| for ([_]Mode{ .idle, .raw, .notified, .short, .productive }) |mode| {
        try sample(mode, pair % 2 != 0, pair);
        try sample(mode, pair % 2 == 0, pair);
    };
}
test {
    _ = scheduling;
}
