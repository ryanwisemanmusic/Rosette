//! Sample host CPU consumed by vkWaitForFences, distinct from elapsed waiting.
//! No GPU timestamps. The FIFO owner samples one call in 64 on its own thread.
const std = @import("std");
const builtin = @import("builtin");
pub const period = 64;
pub const Stamp = struct { cpu: u64, wall: u64 };
pub const Sample = struct { cpu_ns: u64, elapsed_ns: u64 };
fn clock(id: std.c.clockid_t) ?u64 {
    if (builtin.os.tag != .macos and builtin.os.tag != .linux) return null;
    var time: std.c.timespec = undefined;
    if (std.c.clock_gettime(id, &time) != 0 or time.sec < 0 or time.nsec < 0) return null;
    return @as(u64, @intCast(time.sec)) *| std.time.ns_per_s +| @as(u64, @intCast(time.nsec));
}
pub fn begin() ?Stamp {
    return .{ .cpu = clock(.THREAD_CPUTIME_ID) orelse return null, .wall = clock(.MONOTONIC) orelse return null };
}
pub fn finish(start: Stamp) ?Sample {
    const end = begin() orelse return null;
    if (end.cpu < start.cpu or end.wall < start.wall) return null;
    return .{ .cpu_ns = end.cpu - start.cpu, .elapsed_ns = end.wall - start.wall };
}
pub const Row = struct {
    samples: u64 = 0,
    failures: u64 = 0,
    cpu_ns: u64 = 0,
    elapsed_ns: u64 = 0,
    max_cpu_ns: u64 = 0,
    max_elapsed_ns: u64 = 0,
    fn note(self: *Row, value: ?Sample) void {
        const sample = value orelse {
            self.failures +|= 1;
            return;
        };
        self.samples +|= 1;
        self.cpu_ns +|= sample.cpu_ns;
        self.elapsed_ns +|= sample.elapsed_ns;
        self.max_cpu_ns = @max(self.max_cpu_ns, sample.cpu_ns);
        self.max_elapsed_ns = @max(self.max_elapsed_ns, sample.elapsed_ns);
    }
};
pub const Stats = struct {
    inline_wait: Row = .{},
    watcher: Row = .{},
    pub fn note(self: *Stats, inline_wait: bool, value: ?Sample) void {
        (if (inline_wait) &self.inline_wait else &self.watcher).note(value);
    }
    pub fn report(self: Stats) void {
        inline for (.{ "inline_wait", "watcher" }) |scope| {
            const row = @field(self, scope);
            std.log.info("VULKAN FSI OBSERVER HOST CPU: scope={s} samples={d} sample_failures={d} sampled_cpu_ns={d} sampled_cpu_max_ns={d} sampled_elapsed_ns={d} sampled_elapsed_max_ns={d} sample_period={d}; native fence wait on this host thread only, clocks include measurement overhead; scheduling and GPU execution are not CPU time; zero samples is unknown", .{ scope, row.samples, row.failures, row.cpu_ns, row.max_cpu_ns, row.elapsed_ns, row.max_elapsed_ns, period });
        }
    }
};

test "FSI host wait CPU separates parked time and busy CPU without a GPU" {
    const start = begin() orelse return error.SkipZigTest;
    var pause: std.c.timespec = .{ .sec = 0, .nsec = 20_000_000 };
    _ = std.c.nanosleep(&pause, null);
    const parked = finish(start).?;
    try std.testing.expect(parked.cpu_ns < parked.elapsed_ns / 2);
    const busy_start = begin().?;
    var work: u64 = 1;
    while (clock(.THREAD_CPUTIME_ID).? - busy_start.cpu < 2_000_000) work = std.math.rotl(u64, work *% 0x9E3779B97F4A7C15, 7);
    std.mem.doNotOptimizeAway(work);
    const busy = finish(busy_start).?;
    try std.testing.expect(busy.cpu_ns >= 2_000_000);
    var stats: Stats = .{};
    stats.note(true, parked);
    stats.note(false, busy);
    stats.note(false, null);
    try std.testing.expectEqual(@as(u64, 1), stats.inline_wait.samples);
    try std.testing.expectEqual(@as(u64, 1), stats.watcher.samples);
    try std.testing.expectEqual(@as(u64, 1), stats.watcher.failures);
}

test "FSI host wait CPU production FIFO keeps one in 64 observations and every reset" {
    if (begin() == null) return error.SkipZigTest;
    const timing = @import("timing.zig");
    const Fake = struct {
        waits: u64 = 0,
        resets: u64 = 0,
        fn waitFn(context: *anyopaque, _: u64, _: u64) timing.WaitResult {
            const fake: *@This() = @ptrCast(@alignCast(context));
            fake.waits += 1;
            return .signaled;
        }
        fn resetFn(context: *anyopaque, _: u64) bool {
            const fake: *@This() = @ptrCast(@alignCast(context));
            fake.resets += 1;
            return true;
        }
        fn nowFn(_: *anyopaque) u64 {
            return 1000;
        }
    };
    var fake: Fake = .{};
    var monitor = timing.Monitor.init(.{});
    monitor.ops = .{ .context = &fake, .wait = Fake.waitFn, .reset = Fake.resetFn, .now = Fake.nowFn };
    for (0..130) |n| {
        const serial = monitor.track(.{ .fence = n + 1 });
        try std.testing.expect(monitor.pollOnce());
        try std.testing.expectEqual(serial, monitor.stats().completed_serial);
    }
    const stats = monitor.stats();
    try std.testing.expectEqual(@as(u64, 130), fake.waits);
    try std.testing.expectEqual(fake.waits, fake.resets);
    try std.testing.expectEqual(@as(u64, 130), stats.observer.watcher_waits);
    try std.testing.expectEqual(@as(u64, 3), stats.wait_host_cpu.watcher.samples);
    try std.testing.expectEqual(@as(u64, 0), stats.wait_host_cpu.inline_wait.samples);
}
