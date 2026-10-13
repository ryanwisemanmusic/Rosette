//! Name the existing split predicate without changing its limits. The caps
//! returned here are the same samples that determined this draw's decision.
const std = @import("std");
pub const Decision = struct {
    draw_cap: u32,
    work_cap: u64,
    draw_limit: bool,
    work_limit: bool,
    oversized: bool,
    pub fn required(self: Decision) bool {
        return self.draw_limit or self.work_limit;
    }
};
pub fn evaluate(draw_cap: u32, work_cap: u64, draws: u32, work: u64, next: u64) Decision {
    return .{
        .draw_cap = draw_cap,
        .work_cap = work_cap,
        .draw_limit = draws >= draw_cap,
        .work_limit = draws != 0 and (next > work_cap or work > work_cap -| next),
        .oversized = next > work_cap,
    };
}
pub const Profile = struct {
    // Mask bits: draw cap=1, sample-work cap=2, pipeline isolation=4.
    masks: [8]u64 = @splat(0),
    oversized_draws: u64 = 0,
    pub fn note(self: *Profile, decision: Decision, isolation: bool) void {
        const mask: usize = @as(usize, @intFromBool(decision.draw_limit)) |
            (@as(usize, @intFromBool(decision.work_limit)) << 1) |
            (@as(usize, @intFromBool(isolation)) << 2);
        self.masks[mask] +|= 1;
        self.oversized_draws +|= @intFromBool(decision.oversized);
    }
};

test "FSI split decisions retain the exact budget predicate including oversized first draws" {
    const Budget = @import("budget.zig").Budget;
    var budget = Budget.init(.{});
    var random = std.Random.DefaultPrng.init(0x53F51);
    for (0..10000) |_| {
        const r = random.random();
        budget.cap = r.int(u32);
        budget.sample_work_cap = r.int(u64);
        const draws = r.int(u32);
        const work = r.int(u64);
        const next = r.int(u64);
        const decision = evaluate(budget.cap, budget.sample_work_cap, draws, work, next);
        try std.testing.expectEqual(budget.shouldSplit(draws, work, next), decision.required());
    }
    try std.testing.expect(!evaluate(8, 100, 0, 0, 101).required());
    try std.testing.expect(evaluate(8, 100, 1, 0, 101).required());
    try std.testing.expect(!evaluate(8, 100, 1, 20, 80).required());
    try std.testing.expect(evaluate(8, 100, 1, 21, 80).required());
    try std.testing.expect(evaluate(8, 100, 8, 0, 0).required());
}
test "FSI split reason masks retain overlap and first-draw oversize without declaring a split" {
    var profile: Profile = .{};
    for (0..8) |mask| profile.note(.{ .draw_cap = 8, .work_cap = 100, .draw_limit = mask & 1 != 0, .work_limit = mask & 2 != 0, .oversized = false }, mask & 4 != 0);
    for (profile.masks) |count| try std.testing.expectEqual(@as(u64, 1), count);
    profile.note(evaluate(8, 100, 0, 0, 101), false);
    try std.testing.expectEqual(@as(u64, 2), profile.masks[0]);
    try std.testing.expectEqual(@as(u64, 1), profile.oversized_draws);
}

test "FSI monitor split decisions use the caps returned to the recording caller" {
    var monitor = @import("timing.zig").Monitor.init(.{});
    for ([_]u32{ 1, 4, 8, 32 }) |cap| for ([_]u64{ 0, 524288, 8388608, 33554432 }) |work_cap| {
        monitor.cap.store(cap, .monotonic);
        monitor.sample_work_cap.store(work_cap, .monotonic);
        for (0..33) |draws| for ([_]u64{ 0, 737280, 39321600, std.math.maxInt(u64) }) |next| {
            const decision = monitor.splitDecision(@intCast(draws), 737280, next);
            try std.testing.expectEqual(cap, decision.draw_cap);
            try std.testing.expectEqual(work_cap, decision.work_cap);
            try std.testing.expectEqual(monitor.shouldSplit(@intCast(draws), 737280, next), decision.required());
        };
    };
}
