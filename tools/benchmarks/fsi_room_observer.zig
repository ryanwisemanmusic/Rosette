//! Production fence monitor with timed CPU stub fences, never GPU commands.
//! Compare exact before/after monitor sources; checks every FIFO retirement.
const std = @import("std");
const gpu = @import("gpu");
const timing = gpu.vulkan.fsi.timing;
const clock = gpu.vulkan.transport_timing;

const Stub = struct {
    deadlines: [64]std.atomic.Value(u64) = @splat(.init(0)),
    reset_count: std.atomic.Value(u64) = .init(0),
    last_reset: std.atomic.Value(u64) = .init(0),
    invalid: std.atomic.Value(bool) = .init(false),
    fn wait(ctx: *anyopaque, fence: u64, timeout: u64) timing.WaitResult {
        const self: *Stub = @ptrCast(@alignCast(ctx));
        const remaining = self.deadlines[fence % 64].load(.acquire) -| clock.nowNs();
        if (remaining == 0) return .signaled;
        if (timeout == 0) return .timeout;
        const ns = @min(timeout, remaining);
        const delay = std.c.timespec{ .sec = @intCast(ns / std.time.ns_per_s), .nsec = @intCast(ns % std.time.ns_per_s) };
        _ = std.c.nanosleep(&delay, null);
        return if (clock.nowNs() >= self.deadlines[fence % 64].load(.acquire)) .signaled else .timeout;
    }
    fn reset(ctx: *anyopaque, fence: u64) bool {
        const self: *Stub = @ptrCast(@alignCast(ctx));
        if (fence != self.last_reset.load(.monotonic) + 1 or clock.nowNs() < self.deadlines[fence % 64].load(.acquire)) self.invalid.store(true, .monotonic);
        self.last_reset.store(fence, .monotonic);
        _ = self.reset_count.fetchAdd(1, .monotonic);
        return true;
    }
    fn now(_: *anyopaque) u64 {
        return clock.nowNs();
    }
};

fn encode(ns: u64) void {
    const until = clock.nowNs() + ns;
    while (clock.nowNs() < until) std.atomic.spinLoopHint();
}

const Case = struct { name: []const u8, groups: u32, delay: u64, encoding: u64 };
pub fn main() !void {
    const cases = [_]Case{
        .{ .name = "pending-short", .groups = 2000, .delay = 20_000, .encoding = 0 },
        .{ .name = "record-overlap", .groups = 1000, .delay = 20_000, .encoding = 150_000 },
        .{ .name = "pending-medium", .groups = 1000, .delay = 250_000, .encoding = 50_000 },
        .{ .name = "pending-long", .groups = 200, .delay = 2_000_000, .encoding = 50_000 },
        .{ .name = "ready-control", .groups = 5000, .delay = 0, .encoding = 0 },
    };
    for (cases) |case| {
        var stub = Stub{};
        var monitor = timing.Monitor.init(.{});
        try monitor.start(.{ .context = &stub, .wait = Stub.wait, .reset = Stub.reset, .now = Stub.now }, null);
        const start = clock.nowNs();
        var intervals: [5000]u64 = undefined;
        var previous = start;
        for (1..case.groups + 1) |id| {
            try std.testing.expectEqual(timing.RoomResult.available, monitor.waitForSubmitInfos(2, 2));
            // This chunk's predecessor must have retired before fence reuse.
            try std.testing.expectEqual(@as(u64, id - 1), monitor.completedSerial());
            const submitted = clock.nowNs();
            stub.deadlines[id % 64].store(submitted + case.delay, .release);
            try std.testing.expect(!monitor.trackSubmitted(.{ .fence = id, .submit_ns = submitted, .submit_infos = 2, .draws = 8, .sample_work = 1024 }).failed);
            encode(case.encoding);
            const tick = clock.nowNs();
            intervals[id - 1] = tick - previous;
            previous = tick;
        }
        try std.testing.expectEqual(timing.RoomResult.available, monitor.waitForSubmitInfos(2, 2));
        const elapsed = clock.nowNs() - start;
        const stats = monitor.stats();
        monitor.stop();
        try std.testing.expectEqual(@as(u64, case.groups), stats.completed);
        try std.testing.expectEqual(@as(u64, case.groups), stub.reset_count.load(.monotonic));
        try std.testing.expect(!stub.invalid.load(.monotonic));
        try std.testing.expectEqual(@as(usize, 2), stats.max_outstanding_submit_infos);
        try std.testing.expectEqual(@as(u64, 0), stats.budget.risk_events);
        std.mem.sort(u64, intervals[0..case.groups], {}, std.sort.asc(u64));
        const route = if (@hasField(timing.Stats, "observer")) stats.observer else .{ .inline_waits = @as(u64, 0), .inline_completions = @as(u64, 0), .watcher_waits = @as(u64, 0) };
        std.debug.print("room_observer case={s} groups={d} delay_ns={d} encode_ns={d} elapsed_ns={d} p95_ns={d} max_ns={d} cond_waits={d} inline_waits={d} inline_completions={d} watcher_waits={d} ready={d}\n", .{
            case.name, case.groups, case.delay, case.encoding, elapsed, intervals[case.groups * 95 / 100], intervals[case.groups - 1], stats.room_waits, route.inline_waits, route.inline_completions, route.watcher_waits, stats.ready_completions,
        });
    }
}
