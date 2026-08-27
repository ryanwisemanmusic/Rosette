//! Bounded, backend-neutral PM4 packet evidence.
//!
//! The causal log can tell us that a nested walk saw 2,346 packets, but that
//! aggregate alone cannot answer whether the last packet was a wait, a draw,
//! or an emulator extension. This timeline retains a small recent window and
//! monotonic class counters. It performs no logging and never allocates; the
//! process decides when a changed summary is worth printing.

const contract = @import("xenia_pm4_contract");
const pm4 = @import("pm4.zig");

pub const Source = enum(u8) {
    root,
    indirect,

    pub fn label(self: Source) []const u8 {
        return switch (self) {
            .root => "root",
            .indirect => "indirect",
        };
    }
};

pub const SemanticClass = contract.PacketClass;
pub const class_count: usize = @typeInfo(SemanticClass).@"enum".fields.len;

pub const Observation = struct {
    sequence: u64 = 0,
    source: Source = .root,
    depth: u8 = 0,
    stream_address: u32 = 0,
    dword_offset: u32 = 0,
    raw_header: u32 = 0,
    packet_type: pm4.PacketType = .type2,
    opcode: ?pm4.Type3Opcode = null,
    class: SemanticClass = .filler,
    body_dwords: u32 = 0,
    total_dwords: u32 = 1,
    predicated: bool = false,
    executed: bool = true,
};

pub const Summary = struct {
    /// Framed packets, including packets that were skipped by Xenos
    /// predication. This answers what was present in the stream.
    packets: u64 = 0,
    root_packets: u64 = 0,
    nested_packets: u64 = 0,
    /// Packets whose command body was actually dispatched after predication.
    /// This answers what changed Xenos state or submitted work.
    executed_packets: u64 = 0,
    executed_root_packets: u64 = 0,
    executed_nested_packets: u64 = 0,
    root_dwords: u64 = 0,
    nested_dwords: u64 = 0,
    max_depth: u8 = 0,
    class_counts: [class_count]u64 = [_]u64{0} ** class_count,
    executed_class_counts: [class_count]u64 = [_]u64{0} ** class_count,
    last: ?Observation = null,

    pub fn classCount(self: Summary, class: SemanticClass) u64 {
        return self.class_counts[@intCast(@intFromEnum(class))];
    }

    pub fn has(self: Summary, class: SemanticClass) bool {
        return self.classCount(class) != 0;
    }

    pub fn executedClassCount(self: Summary, class: SemanticClass) u64 {
        return self.executed_class_counts[@intCast(@intFromEnum(class))];
    }

    pub fn hasExecuted(self: Summary, class: SemanticClass) bool {
        return self.executedClassCount(class) != 0;
    }
};

pub const Snapshot = struct {
    packets: u64 = 0,
    root_packets: u64 = 0,
    nested_packets: u64 = 0,
    executed_packets: u64 = 0,
    executed_root_packets: u64 = 0,
    executed_nested_packets: u64 = 0,
    root_dwords: u64 = 0,
    nested_dwords: u64 = 0,
    max_depth: u8 = 0,
    class_counts: [class_count]u64 = [_]u64{0} ** class_count,
    executed_class_counts: [class_count]u64 = [_]u64{0} ** class_count,
    last: ?Observation = null,

    pub fn delta(self: Snapshot, before: Snapshot) Summary {
        var result: Summary = .{
            .packets = self.packets - before.packets,
            .root_packets = self.root_packets - before.root_packets,
            .nested_packets = self.nested_packets - before.nested_packets,
            .executed_packets = self.executed_packets - before.executed_packets,
            .executed_root_packets = self.executed_root_packets - before.executed_root_packets,
            .executed_nested_packets = self.executed_nested_packets - before.executed_nested_packets,
            .root_dwords = self.root_dwords - before.root_dwords,
            .nested_dwords = self.nested_dwords - before.nested_dwords,
            .max_depth = self.max_depth,
            .last = self.last,
        };
        for (self.class_counts, 0..) |count, index| {
            result.class_counts[index] = count - before.class_counts[index];
            result.executed_class_counts[index] = self.executed_class_counts[index] - before.executed_class_counts[index];
        }
        return result;
    }
};

pub const Timeline = struct {
    recent: [@import("xenia_gpu_observation_contract").packet_timeline_capacity]Observation = undefined,
    recent_count: usize = 0,
    next_recent: usize = 0,
    packets: u64 = 0,
    root_packets: u64 = 0,
    nested_packets: u64 = 0,
    executed_packets: u64 = 0,
    executed_root_packets: u64 = 0,
    executed_nested_packets: u64 = 0,
    root_dwords: u64 = 0,
    nested_dwords: u64 = 0,
    max_depth: u8 = 0,
    class_counts: [class_count]u64 = [_]u64{0} ** class_count,
    executed_class_counts: [class_count]u64 = [_]u64{0} ** class_count,
    last: ?Observation = null,

    pub fn record(self: *Timeline, observation: Observation) void {
        self.recent[self.next_recent] = observation;
        self.next_recent = (self.next_recent + 1) % self.recent.len;
        if (self.recent_count < self.recent.len) self.recent_count += 1;

        self.packets +|= 1;
        if (observation.source == .root) {
            self.root_packets +|= 1;
            self.root_dwords +|= observation.total_dwords;
        } else {
            self.nested_packets +|= 1;
            self.nested_dwords +|= observation.total_dwords;
        }
        self.max_depth = @max(self.max_depth, observation.depth);
        self.class_counts[@intCast(@intFromEnum(observation.class))] +|= 1;
        if (observation.executed) {
            self.executed_packets +|= 1;
            if (observation.source == .root) {
                self.executed_root_packets +|= 1;
            } else {
                self.executed_nested_packets +|= 1;
            }
            self.executed_class_counts[@intCast(@intFromEnum(observation.class))] +|= 1;
        }
        self.last = observation;
    }

    pub fn snapshot(self: *const Timeline) Snapshot {
        return .{
            .packets = self.packets,
            .root_packets = self.root_packets,
            .nested_packets = self.nested_packets,
            .executed_packets = self.executed_packets,
            .executed_root_packets = self.executed_root_packets,
            .executed_nested_packets = self.executed_nested_packets,
            .root_dwords = self.root_dwords,
            .nested_dwords = self.nested_dwords,
            .max_depth = self.max_depth,
            .class_counts = self.class_counts,
            .executed_class_counts = self.executed_class_counts,
            .last = self.last,
        };
    }

    pub fn latest(self: *const Timeline) ?Observation {
        return self.last;
    }

    pub fn recentSlice(self: *const Timeline, output: []Observation) usize {
        const count = @min(self.recent_count, output.len);
        if (count == 0) return 0;
        const first = if (self.recent_count < self.recent.len)
            0
        else
            self.next_recent;
        const skip = self.recent_count - count;
        for (0..count) |index| {
            output[index] = self.recent[(first + skip + index) % self.recent.len];
        }
        return count;
    }
};

pub fn fromHeader(
    sequence: u64,
    source: Source,
    depth: u8,
    stream_address: u32,
    dword_offset: u32,
    header: pm4.Header,
    executed: bool,
) Observation {
    const class: SemanticClass = switch (header.kind) {
        .type0, .type1 => .state,
        .type2 => .filler,
        .type3 => contract.classifyOpcode(@intCast(@intFromEnum(header.opcode))),
    };
    return .{
        .sequence = sequence,
        .source = source,
        .depth = depth,
        .stream_address = stream_address,
        .dword_offset = dword_offset,
        .raw_header = header.raw,
        .packet_type = header.kind,
        .opcode = if (header.kind == .type3) header.opcode else null,
        .class = class,
        .body_dwords = header.count,
        .total_dwords = header.totalDwords(),
        .predicated = header.predicated,
        .executed = executed,
    };
}

test "packet timeline retains recent packets and class deltas" {
    var timeline: Timeline = .{};
    const draw_header = pm4.decodeHeader(pm4.packetType3(.draw_indx_2, 1, false).?);
    const wait_header = pm4.decodeHeader(pm4.packetType3(.wait_for_idle, 1, false).?);
    timeline.record(fromHeader(1, .root, 0, 0, 0, draw_header, true));
    timeline.record(fromHeader(2, .indirect, 1, 0x1000, 0, wait_header, true));

    const snapshot = timeline.snapshot();
    const before = Snapshot{};
    const summary = snapshot.delta(before);
    try @import("std").testing.expectEqual(@as(u64, 2), summary.packets);
    try @import("std").testing.expectEqual(@as(u64, 1), summary.root_packets);
    try @import("std").testing.expectEqual(@as(u64, 1), summary.nested_packets);
    try @import("std").testing.expectEqual(@as(u64, 1), summary.classCount(.draw));
    try @import("std").testing.expectEqual(@as(u64, 1), summary.classCount(.wait));
    try @import("std").testing.expectEqual(@as(u64, 2), summary.executed_packets);
    try @import("std").testing.expectEqual(@as(u64, 1), summary.executedClassCount(.draw));
    try @import("std").testing.expectEqual(@as(u8, 1), summary.max_depth);
    try @import("std").testing.expectEqual(@as(?pm4.Type3Opcode, .wait_for_idle), summary.last.?.opcode);
}

test "packet timeline separates predicated packets from executed work" {
    var timeline: Timeline = .{};
    const header = pm4.decodeHeader(pm4.packetType3(.draw_indx_2, 1, true).?);
    timeline.record(fromHeader(1, .root, 0, 0, 0, header, false));

    const summary = timeline.snapshot().delta(.{});
    try @import("std").testing.expectEqual(@as(u64, 1), summary.packets);
    try @import("std").testing.expectEqual(@as(u64, 1), summary.classCount(.draw));
    try @import("std").testing.expectEqual(@as(u64, 0), summary.executed_packets);
    try @import("std").testing.expect(!summary.hasExecuted(.draw));
    try @import("std").testing.expect(!summary.last.?.executed);
}

test "packet timeline ring is bounded and preserves the newest records" {
    var timeline: Timeline = .{};
    const header = pm4.decodeHeader(pm4.packetType3(.nop, 1, false).?);
    for (0..timeline.recent.len + 7) |index| {
        timeline.record(fromHeader(@intCast(index + 1), .root, 0, 0, @intCast(index), header, true));
    }
    try @import("std").testing.expectEqual(timeline.recent.len, timeline.recent_count);
    var output: [3]Observation = undefined;
    const count = timeline.recentSlice(&output);
    try @import("std").testing.expectEqual(@as(usize, 3), count);
    try @import("std").testing.expectEqual(@as(u64, timeline.recent.len + 5), output[0].sequence);
    try @import("std").testing.expectEqual(@as(u64, timeline.recent.len + 7), output[2].sequence);
}
