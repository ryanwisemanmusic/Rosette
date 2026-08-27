//! Bounded, contextual PM4 failure evidence.
//!
//! A scalar `packet_errors` count answers only whether something failed. For a
//! circular root ring and recursively executed indirect buffers, the repair
//! depends on where it failed, which header made the claim, and how many dwords
//! were actually available. This journal retains that evidence without heap
//! allocation or logging from the command processor hot path.

const std = @import("std");
const pm4 = @import("pm4.zig");
const packet_trace = @import("packet_trace.zig");

pub const Reason = enum(u8) {
    truncated_packet,
    invalid_packet,
    wait_condition_failed,

    pub fn label(self: Reason) []const u8 {
        return @tagName(self);
    }
};

pub const Record = struct {
    sequence: u64 = 0,
    packet_sequence: u64 = 0,
    source: packet_trace.Source = .root,
    depth: u8 = 0,
    base_address: u32 = 0,
    address: u32 = 0,
    dword_offset: u32 = 0,
    raw_header: u32 = 0,
    kind: pm4.PacketType = .type2,
    opcode: pm4.Type3Opcode = @enumFromInt(0),
    declared_payload_dwords: u32 = 0,
    required_total_dwords: u32 = 0,
    available_dwords: u32 = 0,
    reason: Reason = .invalid_packet,

    pub fn missingDwords(self: Record) u32 {
        return self.required_total_dwords -| self.available_dwords;
    }

    pub fn opcodeLabel(self: Record) []const u8 {
        return if (self.kind == .type3) self.opcode.label() else "-";
    }
};

pub const capacity: usize = 16;

pub const Journal = struct {
    records: [capacity]Record = [_]Record{.{}} ** capacity,
    next: usize = 0,
    count: usize = 0,
    total: u64 = 0,
    overwritten: u64 = 0,

    pub fn record(
        self: *Journal,
        reason: Reason,
        packet_sequence: u64,
        source: packet_trace.Source,
        depth: u8,
        base_address: u32,
        dword_offset: u32,
        header: pm4.Header,
        available_dwords: u32,
    ) void {
        self.total +|= 1;
        self.records[self.next] = .{
            .sequence = self.total,
            .packet_sequence = packet_sequence,
            .source = source,
            .depth = depth,
            .base_address = base_address,
            .address = base_address +% (dword_offset *% 4),
            .dword_offset = dword_offset,
            .raw_header = header.raw,
            .kind = header.kind,
            .opcode = header.opcode,
            .declared_payload_dwords = header.count,
            .required_total_dwords = header.totalDwords(),
            .available_dwords = available_dwords,
            .reason = reason,
        };
        self.next = (self.next + 1) % capacity;
        if (self.count < capacity) {
            self.count += 1;
        } else {
            self.overwritten +|= 1;
        }
    }

    pub fn latest(self: *const Journal) ?Record {
        if (self.count == 0) return null;
        const index = if (self.next == 0) capacity - 1 else self.next - 1;
        return self.records[index];
    }

    /// Oldest-to-newest retained record, convenient for summary logging.
    pub fn retained(self: *const Journal, ordinal: usize) ?Record {
        if (ordinal >= self.count) return null;
        const oldest = if (self.count < capacity) 0 else self.next;
        return self.records[(oldest + ordinal) % capacity];
    }
};

test "truncated packet record carries the missing span and provenance" {
    const raw = pm4.packetType3(.draw_indx, 4, false).?;
    const header = pm4.decodeHeader(raw);
    var journal = Journal{};
    journal.record(.truncated_packet, 12, .indirect, 2, 0x2000, 7, header, 2);
    const fault = journal.latest().?;
    try std.testing.expectEqual(@as(u32, 0x201C), fault.address);
    try std.testing.expectEqual(@as(u32, 5), fault.required_total_dwords);
    try std.testing.expectEqual(@as(u32, 3), fault.missingDwords());
    try std.testing.expectEqualStrings("DRAW_INDX", fault.opcodeLabel());
    try std.testing.expectEqual(packet_trace.Source.indirect, fault.source);
}

test "journal overwrites oldest records without losing totals" {
    const header = pm4.decodeHeader(pm4.packetType2());
    var journal = Journal{};
    var index: usize = 0;
    while (index < capacity + 3) : (index += 1) {
        journal.record(.invalid_packet, index, .root, 0, 0, @intCast(index), header, 1);
    }
    try std.testing.expectEqual(@as(usize, capacity), journal.count);
    try std.testing.expectEqual(@as(u64, capacity + 3), journal.total);
    try std.testing.expectEqual(@as(u64, 3), journal.overwritten);
    try std.testing.expectEqual(@as(u32, 3), journal.retained(0).?.dword_offset);
    try std.testing.expectEqual(@as(u32, capacity + 2), journal.latest().?.dword_offset);
}
