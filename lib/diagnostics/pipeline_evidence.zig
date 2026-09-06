//! Evidence coverage for the x86-hosted Xenia path. A function entry is not
//! its effect, local retention is not upstream coverage, and model/replay work
//! is never promoted into live guest output. This is a report, not a scheduler
//! or an intervention policy.
const std = @import("std");

pub const Coverage = struct {
    armed_step: ?u64 = null,
    through_step: u64 = 0,
    exhaustive: bool = false,
    upstream_lost: u64 = 0,
    local_lost: u64 = 0,

    pub fn negative(self: Coverage, first: u64, last: u64) Negative {
        if (last < first) return .invalid_interval;
        const armed = self.armed_step orelse return .unarmed;
        if (armed > first) return .armed_late;
        if (!self.exhaustive) return .sampled;
        if (self.upstream_lost != 0) return .upstream_loss;
        if (self.local_lost != 0) return .retention_loss;
        if (self.through_step < last) return .stale;
        return .covered;
    }
};

pub const Negative = enum {
    covered,
    unarmed,
    armed_late,
    sampled,
    upstream_loss,
    retention_loss,
    stale,
    invalid_interval,
};

pub const Stage = enum(u8) {
    guest_execution,
    ring_setup,
    ring_publication,
    packet_consumption,
    draw,
    target,
    resolve,
    swap_request,
    swap_decode,
    swap_issue,
    frame_offer,
    frame_completion,

    pub fn label(self: Stage) []const u8 {
        return switch (self) {
            .guest_execution => "guest execution through x86",
            .ring_setup => "ring setup entry",
            .ring_publication => "effective ring publication",
            .packet_consumption => "Xenia type-3 packet entry",
            .draw => "Xenia IssueDraw entry",
            .target => "Xenia render-target update entry",
            .resolve => "guest-visible resolve completion",
            .swap_request => "guest VdSwap entry",
            .swap_decode => "Xenia XE_SWAP decoder entry",
            .swap_issue => "Xenia IssueSwap entry",
            .frame_offer => "authenticated guest frame offered",
            .frame_completion => "authenticated guest frame completed",
        };
    }
};

pub const stage_count = @typeInfo(Stage).@"enum".fields.len;

pub const Origin = enum { unobserved, x86_tracepoint, emulator_counter, canonical_custody, replay, diagnostic, model };
pub const Meaning = enum { entry, effect };
pub const Verdict = enum { unobserved, entry_observed, effect_observed, absent_in_interval, observation_gap, stale, excluded_source };

pub const Row = struct {
    count: u64 = 0,
    origin: Origin = .unobserved,
    meaning: Meaning = .entry,
    first_step: u64 = 0,
    last_step: u64 = 0,
    coverage: Coverage = .{},

    pub fn verdict(self: Row, first: u64, last: u64) Verdict {
        switch (self.origin) {
            .unobserved => return .unobserved,
            .replay, .diagnostic, .model => return .excluded_source,
            else => {},
        }
        if (self.count != 0) return if (self.meaning == .entry) .entry_observed else .effect_observed;
        return switch (self.coverage.negative(first, last)) {
            .covered => .absent_in_interval,
            .stale => .stale,
            else => .observation_gap,
        };
    }
};

pub const Report = struct {
    rows: [stage_count]Row = [_]Row{.{}} ** stage_count,

    pub fn put(self: *Report, stage: Stage, entry: Row) void {
        self.rows[@intFromEnum(stage)] = entry;
    }

    pub fn row(self: *const Report, stage: Stage) Row {
        return self.rows[@intFromEnum(stage)];
    }

    /// A search order, not a universal GPU dependency order. For example a
    /// swap-only title need not draw and a vblank need not consume a packet.
    /// Later observed rows are always printed even when an earlier one is a
    /// hole. Unlike a sequential acceptance ladder, this does not hide them.
    pub fn firstUnobserved(self: *const Report, step: u64) ?Stage {
        for (self.rows, 0..) |value, index| {
            switch (value.verdict(0, step)) {
                .entry_observed, .effect_observed => {},
                else => return @enumFromInt(index),
            }
        }
        return null;
    }

    pub fn fingerprint(self: *const Report, step: u64) u64 {
        var hash: u64 = 0;
        for (self.rows) |value| {
            hash = hash *% 31 +% value.count;
            hash = hash *% 31 +% @intFromEnum(value.verdict(0, step));
        }
        return hash;
    }
};

test "gapless local logging does not establish upstream observation" {
    const coverage = Coverage{ .armed_step = 0, .through_step = 100 };
    try std.testing.expectEqual(Negative.sampled, coverage.negative(0, 100));
    var full = coverage;
    full.exhaustive = true;
    try std.testing.expectEqual(Negative.covered, full.negative(0, 100));
    full.upstream_lost = 1;
    try std.testing.expectEqual(Negative.upstream_loss, full.negative(0, 100));
}

test "late arming and stale checkpoints cannot prove whole-run absence" {
    const coverage = Coverage{ .armed_step = 50, .through_step = 100, .exhaustive = true };
    try std.testing.expectEqual(Negative.armed_late, coverage.negative(0, 100));
    try std.testing.expectEqual(Negative.covered, coverage.negative(50, 100));
    try std.testing.expectEqual(Negative.stale, coverage.negative(50, 101));
    try std.testing.expectEqual(Negative.invalid_interval, coverage.negative(101, 50));
}

test "entry, live effect, and replay are three different claims" {
    var value = Row{ .count = 19, .origin = .x86_tracepoint };
    try std.testing.expectEqual(Verdict.entry_observed, value.verdict(0, 100));
    value.meaning = .effect;
    value.origin = .canonical_custody;
    try std.testing.expectEqual(Verdict.effect_observed, value.verdict(0, 100));
    value.origin = .replay;
    try std.testing.expectEqual(Verdict.excluded_source, value.verdict(0, 100));
}

test "downstream evidence remains visible across an upstream observation hole" {
    var report = Report{};
    report.put(.frame_completion, .{ .count = 1, .origin = .canonical_custody, .meaning = .effect });
    try std.testing.expectEqual(Stage.guest_execution, report.firstUnobserved(100).?);
    try std.testing.expectEqual(Verdict.effect_observed, report.row(.frame_completion).verdict(0, 100));
    try std.testing.expectEqual(Verdict.unobserved, report.row(.resolve).verdict(0, 100));
}
