//! A strict native-present ceiling. Slow frames never accumulate catch-up
//! credit. The caller serializes this policy with the native queue API gate;
//! its sleep callback must release the guest-runtime mutex.
const std = @import("std");
const timing = @import("transport_timing.zig");

pub const Ceiling = struct {
    pub const fps: u32 = 30;
    // Round upward: rounding down could issue slightly more than 30/s.
    pub const interval_ns: u64 = (std.time.ns_per_s + fps - 1) / fps;
    last_attempt_ns: u64 = 0,
    waits: u64 = 0,
    waited_ns: u64 = 0,
    refused: u64 = 0,

    pub fn deadline(self: *const Ceiling, now: u64) ?u64 {
        if (now == 0 or (self.last_attempt_ns != 0 and now < self.last_attempt_ns)) return null;
        if (self.last_attempt_ns == 0) return now;
        return @max(now, self.last_attempt_ns +| interval_ns);
    }

    pub fn attempted(self: *Ceiling, now: u64) void {
        self.last_attempt_ns = now;
    }
};

/// Only copied host scalars are used while the runtime mutex is released.
pub const Wait = struct {
    deadline_ns: u64,
    succeeded: bool = false,
    elapsed_ns: u64 = 0,

    pub fn run(self: *Wait) void {
        const started = timing.nowNs();
        if (started == 0) return;
        while (true) {
            const now = timing.nowNs();
            if (now == 0 or now < started) return;
            if (now >= self.deadline_ns) {
                self.elapsed_ns = now - started;
                self.succeeded = true;
                return;
            }
            const remaining = self.deadline_ns - now;
            const request: std.c.timespec = .{
                .sec = @intCast(remaining / std.time.ns_per_s),
                .nsec = @intCast(remaining % std.time.ns_per_s),
            };
            // EINTR/early wakeups recheck the deadline; never busy-poll.
            if (std.c.nanosleep(&request, null) != 0 and std.c._errno().* != @intFromEnum(std.c.E.INTR)) return;
        }
    }
};

test "presentation ceiling spaces attempts at no more than 30 FPS" {
    var policy: Ceiling = .{};
    var now: u64 = 1_000_000_000;
    for (0..300) |_| {
        const deadline = policy.deadline(now).?;
        if (policy.last_attempt_ns != 0) try std.testing.expect(deadline - policy.last_attempt_ns >= Ceiling.interval_ns);
        policy.attempted(deadline);
        now = deadline + 1;
    }
    try std.testing.expect(@as(f64, 1_000_000_000) / @as(f64, @floatFromInt(Ceiling.interval_ns)) <= 30.0);
}

test "presentation ceiling adds no wait to slow frames and never catches up" {
    var policy: Ceiling = .{};
    policy.attempted(1_000_000_000);
    try std.testing.expectEqual(@as(?u64, 2_000_000_000), policy.deadline(2_000_000_000));
    policy.attempted(2_000_000_000);
    try std.testing.expectEqual(@as(?u64, 2_000_000_000 + Ceiling.interval_ns), policy.deadline(2_000_000_001));
}

test "presentation ceiling rejects missing or regressing clocks" {
    var policy: Ceiling = .{};
    try std.testing.expect(policy.deadline(0) == null);
    policy.attempted(2_000_000_000);
    try std.testing.expect(policy.deadline(1_000_000_000) == null);
}

test "presentation ceiling wait reaches its host deadline" {
    const now = timing.nowNs();
    if (now == 0) return error.SkipZigTest;
    var wait: Wait = .{ .deadline_ns = now + 1_000_000 };
    Wait.run(&wait);
    try std.testing.expect(wait.succeeded);
    try std.testing.expect(timing.nowNs() >= wait.deadline_ns);
}
