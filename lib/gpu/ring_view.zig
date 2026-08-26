//! Which projection of the ring buffer actually holds the packets.
//!
//! The emulated console's physical memory is mapped into this process more than
//! once. The same ring buffer is reachable through a physical view, through a
//! virtual alias in the console's `0xE0000000` window, and through the raw
//! mapping base without the emulator's 4 KiB heap bias. Three host addresses,
//! one buffer — except that on this platform they are *not* one buffer: the
//! bias puts two of them on different host pages, and a store through one is
//! invisible through another.
//!
//! That produces a failure with no error in it. The run reports that the
//! producer advanced the write pointer by twenty-five dwords, and a reader
//! looking at the ring finds eight thousand dwords of zeros. Both are true. The
//! reader was looking at the wrong projection, and "the guest published" and
//! "the ring is empty" then sit in the same log contradicting each other with
//! nothing to arbitrate between them.
//!
//! So a ring read never picks one address. It reads every projection it has,
//! scores each by whether it contains anything that looks like a command
//! stream, and reports all of them — because the disagreement between them is
//! itself the finding. A run where one alias holds packets and another holds
//! zeros has located an aliasing defect; a run where all of them are empty has
//! proved the producer wrote nothing, which no single-address read can do.
//!
//! Deliberately holds no memory and performs no translation. The caller
//! supplies the candidate addresses because the caller owns the address-space
//! model; this owns the question of which one to believe.

const std = @import("std");
const pm4 = @import("pm4.zig");
const ring_payload = @import("ring_payload.zig");
const ring_scan = @import("ring_scan.zig");

/// Which projection of console memory an address came from. Named rather than
/// indexed so a report says where it looked, not which slot of an array it was.
pub const Projection = enum(u8) {
    /// `TranslatePhysical`: the physical view of console memory.
    physical,
    /// The `0xE0000000` virtual alias, translated with the emulator's 4 KiB
    /// heap bias. This is what `TranslateVirtual` reaches.
    virtual_biased,
    /// `virtual_membase_ + address`, with no bias. Code inside the emulator
    /// that does the addition itself lands here, and on this platform that is a
    /// different host page from the biased form.
    virtual_unbiased,

    pub fn label(self: Projection) []const u8 {
        return switch (self) {
            .physical => "physical",
            .virtual_biased => "virtual_biased",
            .virtual_unbiased => "virtual_unbiased",
        };
    }

    pub fn meaning(self: Projection) []const u8 {
        return switch (self) {
            .physical => "the physical view. The command processor reads the ring through this one",
            .virtual_biased => "the E000 virtual alias with the emulator's 4 KiB heap bias, which is what its own TranslateVirtual reaches",
            .virtual_unbiased => "the mapping base plus the console address, with no bias. Emulator code that does the addition inline lands here, and on this platform that is a different host page from the biased form",
        };
    }
};

pub const projection_count = 3;

/// What one projection of the ring contained.
pub const Reading = struct {
    projection: Projection,
    /// Host address this projection resolved to. Zero when the caller had no
    /// translation for it, which is different from a translation that resolved
    /// to unreadable memory.
    address: u64 = 0,
    readable: bool = false,
    /// Dwords that were not zero. The cheapest possible "has anything ever been
    /// written here", and the one that does not depend on the dwords parsing as
    /// packets.
    nonzero_dwords: u32 = 0,
    /// Packets a walk from the ring's origin recognised.
    packets: u32 = 0,
    draws: u32 = 0,
    stream_validated: bool = false,
    swap: ?pm4.SwapDescription = null,
    fetch: ?pm4.FetchConstant = null,
    swap_candidates: u32 = 0,
    swap_payload_readable: u32 = 0,
    swap_malformed_candidates: u32 = 0,
    swap_truncated_candidates: u32 = 0,
    /// Header dword offset of a retained XE_SWAP candidate.  The offset is
    /// retained even though this view is not the authoritative consumer.
    swap_offset: ?u32 = null,

    /// Whether this projection holds something a producer wrote. Deliberately
    /// weaker than "parses as a packet stream": a ring written from an offset
    /// the walk does not start at still proves the producer wrote *here*, which
    /// is the fact that separates the three aliases.
    pub fn written(self: Reading) bool {
        return self.readable and self.nonzero_dwords != 0;
    }

    /// How strongly this projection looks like the real ring. Used only to
    /// order candidates; the report always lists all of them.
    pub fn score(self: Reading) u32 {
        if (!self.readable) return 0;
        // A zero dword is a syntactically valid type-0 header claiming one
        // payload dword, so a ring of nothing walks as four thousand perfectly
        // well-formed packets. Without this an untouched alias outscores a
        // written one, which is the exact inversion this module exists to
        // prevent.
        if (self.nonzero_dwords == 0) return 0;
        var value: u32 = 0;
        if (self.nonzero_dwords != 0) value += 1;
        if (self.packets != 0) value += 2;
        if (self.draws != 0) value += 4;
        if (self.swap_candidates != 0) value += 4;
        if (self.swap != null) value += 8;
        return value;
    }
};

/// Every projection, and what the disagreement between them means.
pub const Survey = struct {
    readings: [projection_count]Reading = .{
        .{ .projection = .physical },
        .{ .projection = .virtual_biased },
        .{ .projection = .virtual_unbiased },
    },

    pub fn record(self: *Survey, reading: Reading) void {
        self.readings[@intFromEnum(reading.projection)] = reading;
    }

    /// The projection most likely to be the ring the producer wrote.
    pub fn best(self: *const Survey) ?Reading {
        var chosen: ?Reading = null;
        for (self.readings) |reading| {
            if (reading.score() == 0) continue;
            if (chosen == null or reading.score() > chosen.?.score()) chosen = reading;
        }
        return chosen;
    }

    pub fn readableCount(self: *const Survey) u32 {
        var count: u32 = 0;
        for (self.readings) |reading| {
            if (reading.readable) count += 1;
        }
        return count;
    }

    pub fn writtenCount(self: *const Survey) u32 {
        var count: u32 = 0;
        for (self.readings) |reading| {
            if (reading.written()) count += 1;
        }
        return count;
    }

    pub fn swapCandidateCount(self: *const Survey) u32 {
        var count: u32 = 0;
        for (self.readings) |reading| count += reading.swap_candidates;
        return count;
    }

    pub fn readableSwapCandidateCount(self: *const Survey) u32 {
        var count: u32 = 0;
        for (self.readings) |reading| count += reading.swap_payload_readable;
        return count;
    }

    /// True when at least one projection holds data and at least one other
    /// readable projection does not. This is the aliasing defect: the same
    /// console address reaching two different host pages.
    pub fn aliasesDisagree(self: *const Survey) bool {
        if (self.writtenCount() == 0) return false;
        return self.writtenCount() < self.readableCount();
    }

    /// One sentence a reader can act on. The three outcomes have three
    /// different owners, which is the entire reason to survey rather than pick.
    pub fn verdict(self: *const Survey, producer_published: bool) []const u8 {
        if (self.readableCount() == 0)
            return "no projection of the ring is readable. The geometry is known and none of the three host addresses the console's physical page maps to can be read, which is an address-space disagreement and not a graphics fault";
        if (self.aliasesDisagree())
            return "the projections disagree: one alias of the ring holds data and another readable alias does not. The same console address is reaching two different host pages, so a store through one is invisible through the other — this is an aliasing defect, and whichever half the command processor reads is the half that decides whether it sees any work";
        if (self.writtenCount() != 0)
            return "every readable projection agrees and holds data, so the ring is a single consistent buffer and what is in it is what the producer wrote";
        if (producer_published)
            return "every readable projection of the ring is entirely zero while the producer is recorded as having advanced the write pointer. The pointer moved and no dword was written: the producer published an empty span, which is a submission path that ran without a batch behind it rather than a batch the consumer missed";
        return "every readable projection of the ring is entirely zero and the producer never advanced the write pointer. Nothing has been submitted and nothing has been lost";
    }
};

/// Examine one projection. `bytes` is the caller's window onto that projection,
/// already resolved and bounds-checked.
pub fn examine(projection: Projection, address: u64, bytes: ?[]const u8, ring_dwords: u32) Reading {
    var reading = Reading{ .projection = projection, .address = address };
    const data = bytes orelse return reading;
    if (ring_dwords == 0 or data.len < @as(usize, ring_dwords) * 4) return reading;
    reading.readable = true;

    const limit = @min(ring_dwords, ring_scan.max_search_dwords);
    var index: u32 = 0;
    while (index < limit) : (index += 1) {
        if (std.mem.readInt(u32, data[index * 4 ..][0..4], .big) != 0) reading.nonzero_dwords += 1;
    }

    // An entirely zero window has nothing to walk, and walking it would report
    // thousands of well-formed type-0 packets made of nothing.
    if (reading.nonzero_dwords == 0) return reading;

    // Counted from the written regions only. A walk across the whole ring
    // counts one packet per zero dword, so an eight-thousand-dword ring holding
    // seventeen written dwords reported two thousand packets — a number that
    // describes the fill, not the producer.
    const written = ring_payload.digest(data, ring_dwords, limit);
    reading.packets = written.real_packets;
    reading.draws = written.draws;
    reading.stream_validated = written.stream_validated;
    const evidence = ring_scan.findSwapEvidence(data, ring_dwords);
    reading.swap_candidates = evidence.candidates;
    reading.swap_payload_readable = evidence.payload_readable;
    reading.swap_malformed_candidates = evidence.malformed;
    reading.swap_truncated_candidates = evidence.truncated;
    if (evidence.first_decoded) |found| {
        reading.swap = found.swap;
        reading.fetch = found.fetch;
        reading.swap_offset = found.offset;
    } else {
        reading.swap_offset = evidence.first_offset;
    }
    return reading;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn ringImage(comptime dwords: u32, values: []const u32) [dwords * 4]u8 {
    var bytes = [_]u8{0} ** (dwords * 4);
    for (values, 0..) |value, index| {
        std.mem.writeInt(u32, bytes[index * 4 ..][0..4], value, .big);
    }
    return bytes;
}

test "a projection with no translation is distinguished from one that is unreadable" {
    const missing = examine(.physical, 0, null, 64);
    try std.testing.expect(!missing.readable);
    try std.testing.expectEqual(@as(u64, 0), missing.address);

    const short = [_]u8{0} ** 16;
    const truncated = examine(.virtual_biased, 0x1000, &short, 64);
    try std.testing.expect(!truncated.readable);
    // The address is still reported: the translation worked and the memory did
    // not, which is a different thing to fix.
    try std.testing.expectEqual(@as(u64, 0x1000), truncated.address);
}

// The failure this module exists for. The producer published, one alias holds
// the packets, and a reader looking at the other alias sees an empty ring.
test "an alias holding packets and one holding zeros is reported as a disagreement" {
    const written = ringImage(64, &.{
        pm4.packetType3(.set_constant, 2, false).?, 0, 0,
        pm4.packetType3(.draw_indx_2, 2, false).?,  0, 0,
    });
    const empty = ringImage(64, &.{});

    var survey = Survey{};
    survey.record(examine(.physical, 0x46d4eb000, &empty, 64));
    survey.record(examine(.virtual_biased, 0x44d4eb000, &written, 64));

    try std.testing.expectEqual(@as(u32, 2), survey.readableCount());
    try std.testing.expectEqual(@as(u32, 1), survey.writtenCount());
    try std.testing.expect(survey.aliasesDisagree());
    try std.testing.expect(std.mem.indexOf(u8, survey.verdict(true), "aliasing defect") != null);

    // And the alias that holds the work is the one chosen.
    const best = survey.best().?;
    try std.testing.expectEqual(Projection.virtual_biased, best.projection);
    try std.testing.expectEqual(@as(u32, 1), best.draws);
}

test "a readable projection does not imply a readable XE_SWAP payload" {
    const bytes = ringImage(64, &.{
        pm4.packetType3(.set_constant, 2, false).?, 0x11, 0x22,
        pm4.packetType3(.draw_indx_2, 2, false).?,  0x33, 0x44,
    });
    const reading = examine(.physical, 0x1000, &bytes, 64);
    try std.testing.expect(reading.readable);
    try std.testing.expect(reading.packets != 0);
    try std.testing.expectEqual(@as(u32, 0), reading.swap_candidates);
    try std.testing.expectEqual(@as(u32, 0), reading.swap_payload_readable);
    try std.testing.expect(reading.swap == null);
}

// The other half of the same question, and the one a single-address read can
// never answer: the pointer moved and nothing was written anywhere.
test "every projection empty with a published producer names an empty submission" {
    const empty = ringImage(64, &.{});
    var survey = Survey{};
    survey.record(examine(.physical, 0x1000, &empty, 64));
    survey.record(examine(.virtual_biased, 0x2000, &empty, 64));
    survey.record(examine(.virtual_unbiased, 0x3000, &empty, 64));

    try std.testing.expectEqual(@as(u32, 3), survey.readableCount());
    try std.testing.expectEqual(@as(u32, 0), survey.writtenCount());
    try std.testing.expect(!survey.aliasesDisagree());
    // A ring of zeros walks as thousands of well-formed type-0 packets, so a
    // reading that counted them would make an untouched alias the best
    // candidate. It has to score zero.
    try std.testing.expect(survey.best() == null);
    for (survey.readings) |reading| try std.testing.expectEqual(@as(u32, 0), reading.packets);

    try std.testing.expect(std.mem.indexOf(u8, survey.verdict(true), "published an empty span") != null);
    // And with no publication, the same emptiness means something else.
    try std.testing.expect(std.mem.indexOf(u8, survey.verdict(false), "nothing has been lost") != null);
}

test "agreeing projections are not reported as a defect" {
    const written = ringImage(64, &.{ pm4.packetType3(.set_constant, 2, false).?, 0, 0 });
    var survey = Survey{};
    survey.record(examine(.physical, 0x1000, &written, 64));
    survey.record(examine(.virtual_biased, 0x2000, &written, 64));

    try std.testing.expect(!survey.aliasesDisagree());
    try std.testing.expectEqual(@as(u32, 2), survey.writtenCount());
    try std.testing.expect(std.mem.indexOf(u8, survey.verdict(true), "single consistent buffer") != null);
}

// A ring written from an offset the packet walk does not start at still proves
// the producer wrote *here*, which is the fact that separates the aliases.
test "data that does not parse as packets still proves the alias was written" {
    var bytes = [_]u8{0} ** 256;
    std.mem.writeInt(u32, bytes[128..][0..4], 0xDEAD_BEEF, .big);
    const reading = examine(.physical, 0x1000, &bytes, 64);
    try std.testing.expect(reading.written());
    try std.testing.expectEqual(@as(u32, 1), reading.nonzero_dwords);
    try std.testing.expect(reading.score() > 0);
}

test "a swap outranks a draw which outranks bare data when choosing an alias" {
    const bare = ringImage(64, &.{0x1111_2222});
    const drew = ringImage(64, &.{ pm4.packetType3(.draw_indx, 1, false).?, 0 });
    var swapped: [12]u32 = undefined;
    _ = pm4.encodeSwapSequence(&swapped, .{}, .{
        .frontbuffer_physical_address = 0x1FC0_0000,
        .width = 1280,
        .height = 720,
    }, 12).?;
    const with_swap = ringImage(64, &swapped);

    var survey = Survey{};
    survey.record(examine(.physical, 1, &bare, 64));
    survey.record(examine(.virtual_biased, 2, &drew, 64));
    survey.record(examine(.virtual_unbiased, 3, &with_swap, 64));
    try std.testing.expectEqual(Projection.virtual_unbiased, survey.best().?.projection);
    try std.testing.expectEqual(@as(u32, 1280), survey.best().?.swap.?.width);
    try std.testing.expectEqual(@as(u32, 7), survey.best().?.swap_offset.?);
}

test "every projection names where it looked rather than which slot it was" {
    inline for (.{ Projection.physical, Projection.virtual_biased, Projection.virtual_unbiased }) |projection| {
        try std.testing.expect(projection.label().len > 0);
        try std.testing.expect(projection.meaning().len > 30);
    }
}

test "an unreadable survey says so rather than reporting an empty ring" {
    var survey = Survey{};
    try std.testing.expectEqual(@as(u32, 0), survey.readableCount());
    try std.testing.expect(std.mem.indexOf(u8, survey.verdict(true), "no projection of the ring is readable") != null);
}
