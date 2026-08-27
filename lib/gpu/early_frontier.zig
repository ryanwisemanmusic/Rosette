//! Runtime evidence ledger for the earliest GPU handoff boundaries.
//!
//! `xenia_gpu_observation_contract` defines what the boundaries mean and which
//! facts precede them. This module records what actually happened during one
//! run. It is intentionally silent and allocation-free: the Mach-O process
//! decides whether a changed frontier deserves a log line.

const contract = @import("xenia_gpu_observation_contract");

pub const Boundary = contract.Boundary;

pub const Source = enum(u8) {
    startup,
    tracepoint,
    ring,
    pm4,
    xenos,
    scheduler,
    presenter,
    controller,

    pub fn label(self: Source) []const u8 {
        return switch (self) {
            .startup => "startup",
            .tracepoint => "tracepoint",
            .ring => "ring",
            .pm4 => "pm4",
            .xenos => "xenos",
            .scheduler => "scheduler",
            .presenter => "presenter",
            .controller => "controller",
        };
    }

    fn bit(self: Source) u16 {
        return @as(u16, 1) << @as(u4, @intCast(@intFromEnum(self)));
    }
};

pub const Edge = struct {
    seen: bool = false,
    count: u64 = 0,
    first_step: u64 = 0,
    last_step: u64 = 0,
    first_value: u64 = 0,
    last_value: u64 = 0,
    source_mask: u16 = 0,
};

pub const Snapshot = struct {
    observed_mask: u32 = 0,
    actionable_mask: u32 = 0,
    total_observations: u64 = 0,
    last_step: u64 = 0,
    last_boundary: ?Boundary = null,
};

pub const Ledger = struct {
    edges: [contract.boundary_count]Edge = [_]Edge{.{}} ** contract.boundary_count,
    observed_mask: u32 = 0,
    total_observations: u64 = 0,
    last_step: u64 = 0,
    last_boundary: ?Boundary = null,
    has_step: bool = false,

    pub fn observe(self: *Ledger, boundary: Boundary, step: u64, source: Source, value: u64) void {
        const index = @intFromEnum(boundary);
        var record = &self.edges[index];
        if (!record.seen) {
            record.seen = true;
            record.first_step = step;
            record.first_value = value;
            self.observed_mask |= contract.bit(boundary);
        }
        record.count +|= 1;
        record.last_step = step;
        record.last_value = value;
        record.source_mask |= source.bit();
        self.total_observations +|= 1;
        if (!self.has_step or step >= self.last_step) {
            self.has_step = true;
            self.last_step = step;
            self.last_boundary = boundary;
        }
    }

    pub fn observed(self: *const Ledger, boundary: Boundary) bool {
        return (self.observed_mask & contract.bit(boundary)) != 0;
    }

    pub fn edge(self: *const Ledger, boundary: Boundary) Edge {
        return self.edges[@intFromEnum(boundary)];
    }

    pub fn actionableMask(self: *const Ledger) u32 {
        return contract.actionableMask(self.observed_mask);
    }

    pub fn firstUnmet(self: *const Ledger) ?Boundary {
        inline for (@typeInfo(Boundary).@"enum".fields) |field| {
            const boundary: Boundary = @enumFromInt(field.value);
            if (!self.observed(boundary)) return boundary;
        }
        return null;
    }

    pub fn firstActionable(self: *const Ledger) ?Boundary {
        const actionable = self.actionableMask();
        inline for (@typeInfo(Boundary).@"enum".fields) |field| {
            const boundary: Boundary = @enumFromInt(field.value);
            if ((actionable & contract.bit(boundary)) != 0) return boundary;
        }
        return null;
    }

    pub fn quietSteps(self: *const Ledger, now: u64) ?u64 {
        if (!self.has_step) return null;
        return if (now >= self.last_step) now - self.last_step else 0;
    }

    pub fn snapshot(self: *const Ledger) Snapshot {
        return .{
            .observed_mask = self.observed_mask,
            .actionable_mask = self.actionableMask(),
            .total_observations = self.total_observations,
            .last_step = self.last_step,
            .last_boundary = self.last_boundary,
        };
    }

    /// A compact change key for report gating. It includes edge counts and
    /// values, not just the observed mask, so a repeated boundary with a new
    /// packet address can still explain a changed producer path.
    pub fn fingerprint(self: *const Ledger) u64 {
        var result: u64 = 0xcbf2_9ce4_8422_2325;
        result ^= self.observed_mask;
        result *%= 0x0000_0100_0000_01B3;
        inline for (@typeInfo(Boundary).@"enum".fields) |field| {
            const boundary: Boundary = @enumFromInt(field.value);
            const record = self.edge(boundary);
            result ^= record.count;
            result *%= 0x0000_0100_0000_01B3;
            result ^= record.last_value;
            result *%= 0x0000_0100_0000_01B3;
        }
        return result;
    }
};

test "early frontier tracks ownership-independent evidence and actionable gaps" {
    var ledger: Ledger = .{};
    ledger.observe(.ring_publication, 10, .ring, 0x1000);
    ledger.observe(.ring_payload_readable, 11, .ring, 32);
    ledger.observe(.root_pm4_consumed, 12, .pm4, 8);
    ledger.observe(.draw_submitted, 13, .xenos, 3);
    try @import("std").testing.expect(ledger.observed(.draw_submitted));
    try @import("std").testing.expect(ledger.firstActionable() != null);
    try @import("std").testing.expectEqual(@as(u64, 1), ledger.edge(.draw_submitted).count);
    try @import("std").testing.expectEqual(@as(u16, 1 << @intFromEnum(Source.xenos)), ledger.edge(.draw_submitted).source_mask);
    try @import("std").testing.expectEqual(@as(?u64, 0), ledger.quietSteps(13));
}

test "frontier never treats PM4 evidence as guest VdSwap evidence" {
    var ledger: Ledger = .{};
    ledger.observe(.root_pm4_consumed, 100, .pm4, 72);
    ledger.observe(.draw_submitted, 101, .xenos, 24);
    try @import("std").testing.expect(!ledger.observed(.guest_vdswap_entered));
    try @import("std").testing.expect(!ledger.observed(.guest_swap_encoded));
    try @import("std").testing.expect(ledger.actionableMask() & contract.bit(.guest_vdswap_entered) != 0);
}

test "frontier fingerprint changes when an observed edge receives new evidence" {
    var ledger: Ledger = .{};
    const before = ledger.fingerprint();
    ledger.observe(.ring_publication, 1, .ring, 0x1000);
    const after = ledger.fingerprint();
    try @import("std").testing.expect(before != after);
}
