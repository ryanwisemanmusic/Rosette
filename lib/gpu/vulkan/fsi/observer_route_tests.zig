const std = @import("std");
const timing = @import("timing.zig");
const clock = @import("../transport_timing.zig");

const Driver = struct {
    now_ns: std.atomic.Value(u64) = .init(0),
    done_ns: u64 = 400_000_000,
    fail_wait: bool = false,
    fail_reset: bool = false,
    resets: u32 = 0,
    positive_calls: std.atomic.Value(u32) = .init(0),
    calls_active: std.atomic.Value(u32) = .init(0),
    concurrent: std.atomic.Value(bool) = .init(false),
    hold: std.atomic.Value(bool) = .init(false),
    fn wait(ctx: *anyopaque, _: u64, timeout: u64) timing.WaitResult {
        const self: *Driver = @ptrCast(@alignCast(ctx));
        if (self.calls_active.fetchAdd(1, .acq_rel) != 0) self.concurrent.store(true, .release);
        defer _ = self.calls_active.fetchSub(1, .acq_rel);
        if (timeout == 0) return .timeout;
        _ = self.positive_calls.fetchAdd(1, .release);
        while (self.hold.load(.acquire)) std.Thread.yield() catch {};
        if (self.fail_wait) return .failed;
        const tick = self.now_ns.fetchAdd(timeout, .monotonic) + timeout;
        return if (tick >= self.done_ns) .signaled else .timeout;
    }
    fn reset(ctx: *anyopaque, _: u64) bool {
        const self: *Driver = @ptrCast(@alignCast(ctx));
        self.resets += 1;
        return !self.fail_reset;
    }
    fn now(ctx: *anyopaque) u64 {
        const self: *Driver = @ptrCast(@alignCast(ctx));
        return self.now_ns.load(.monotonic);
    }
    fn ops(self: *Driver) timing.FenceOps {
        return .{ .context = self, .wait = wait, .reset = reset, .now = now };
    }
};

test "FSI room observer keeps risk, severe recovery, retirement and failed reset custody" {
    for (0..3) |mode| {
        var driver = Driver{ .fail_wait = mode == 1, .fail_reset = mode == 2 };
        var monitor = timing.Monitor.init(.{});
        try monitor.start(driver.ops(), null);
        defer monitor.stop();
        const tracked = monitor.trackSubmitted(.{ .fence = 17, .submit_infos = 2, .draws = 16, .sample_work = 2 * 1024 * 1024 });
        try std.testing.expect(!tracked.failed);
        try std.testing.expectEqual(if (mode == 0) timing.RoomResult.available else .failed, monitor.waitForSubmitInfos(2, 2));
        const stats = monitor.stats();
        try std.testing.expectEqual(@as(u64, if (mode == 1) 0 else 1), stats.budget.risk_events);
        try std.testing.expectEqual(@as(u64, if (mode == 1) 0 else 1), stats.budget.severe_events);
        try std.testing.expectEqual(@as(u64, if (mode == 0) 1 else 0), stats.completed_serial);
        try std.testing.expectEqual(@as(usize, if (mode == 0) 0 else 2), stats.outstanding_submit_infos);
        try std.testing.expectEqual(@as(?u64, if (mode == 0) 17 else null), monitor.takeFence());
        if (mode == 0) {
            try std.testing.expectEqual(@as(u32, 4), stats.budget.cap);
            try std.testing.expect(stats.budget.emergency);
            try std.testing.expectEqual(@as(u64, 1), stats.severe_recoveries);
            try std.testing.expectEqual(@as(u64, 400_000_000), stats.budget.total_observed_ns);
            try std.testing.expect(stats.observer.inline_timeouts > 0);
        }
        try std.testing.expect(!driver.concurrent.load(.acquire));
    }
}

test "FSI room observer shutdown joins an active native wait before fence destruction" {
    var driver = Driver{ .done_ns = 1, .hold = .init(true) };
    var monitor = timing.Monitor.init(.{});
    try monitor.start(driver.ops(), null);
    defer monitor.stop();
    _ = monitor.trackSubmitted(.{ .fence = 3, .submit_infos = 2 });
    const Room = struct {
        result: timing.RoomResult = .failed,
        fn run(self: *@This(), mon: *timing.Monitor) void {
            self.result = mon.waitForSubmitInfos(2, 2);
        }
    };
    var room = Room{};
    const waiter = try std.Thread.spawn(.{}, Room.run, .{ &room, &monitor });
    while (driver.positive_calls.load(.acquire) == 0) std.Thread.yield() catch {};
    const Stop = struct {
        done: std.atomic.Value(bool) = .init(false),
        fn run(self: *@This(), mon: *timing.Monitor) void {
            mon.stop();
            self.done.store(true, .release);
        }
    };
    var stopped = Stop{};
    const stopper = try std.Thread.spawn(.{}, Stop.run, .{ &stopped, &monitor });
    const deadline = clock.nowNs() + 2_000_000;
    while (clock.nowNs() < deadline) std.Thread.yield() catch {};
    try std.testing.expect(!stopped.done.load(.acquire));
    driver.hold.store(false, .release);
    waiter.join();
    stopper.join();
    try std.testing.expectEqual(timing.RoomResult.stopped, room.result);
    try std.testing.expectEqual(@as(u32, 0), driver.calls_active.load(.acquire));
    try std.testing.expect(!driver.concurrent.load(.acquire));
    try std.testing.expect(stopped.done.load(.acquire));
}

test "FSI full group without a room waiter still reaches the watcher" {
    var driver = Driver{ .done_ns = 1 };
    var monitor = timing.Monitor.init(.{});
    try monitor.start(driver.ops(), null);
    defer monitor.stop();
    const tracked = monitor.trackSubmitted(.{ .fence = 9, .submit_infos = 2 });
    const deadline = clock.nowNs() + 1_000_000_000;
    while (monitor.completedSerial() != tracked.serial and clock.nowNs() < deadline) std.Thread.yield() catch {};
    try std.testing.expectEqual(tracked.serial, monitor.completedSerial());
    const stats = monitor.stats();
    try std.testing.expectEqual(@as(u64, 0), stats.observer.inline_waits);
    try std.testing.expect(stats.observer.watcher_waits > 0);
}

test "FSI concurrent room waiters and watcher never reset the same head twice" {
    var driver = Driver{ .done_ns = 1, .hold = .init(true) };
    var monitor = timing.Monitor.init(.{});
    try monitor.start(driver.ops(), null);
    defer monitor.stop();
    _ = monitor.trackSubmitted(.{ .fence = 1, .submit_infos = 2 });
    const Room = struct {
        result: timing.RoomResult = .failed,
        fn run(self: *@This(), mon: *timing.Monitor) void {
            self.result = mon.waitForSubmitInfos(2, 2);
        }
    };
    var rooms = [_]Room{ .{}, .{} };
    const first = try std.Thread.spawn(.{}, Room.run, .{ &rooms[0], &monitor });
    const second = try std.Thread.spawn(.{}, Room.run, .{ &rooms[1], &monitor });
    while (driver.positive_calls.load(.acquire) == 0) std.Thread.yield() catch {};
    driver.hold.store(false, .release);
    first.join();
    second.join();
    try std.testing.expectEqual(timing.RoomResult.available, rooms[0].result);
    try std.testing.expectEqual(timing.RoomResult.available, rooms[1].result);
    try std.testing.expectEqual(@as(u32, 1), driver.resets);
    try std.testing.expect(!driver.concurrent.load(.acquire));
    try std.testing.expectEqual(@as(u64, 1), monitor.stats().completed_serial);
}
