//! The dwords the producer actually wrote, printed.
//!
//! A ring of 8192 dwords holding 17 non-zero ones is a very specific fact, and
//! every summary built on top of it loses the only part that matters. "Packets:
//! 2038" is an artifact — a zero dword is a syntactically valid type-0 header,
//! so an empty ring walks as thousands of well-formed packets. "Draws: 0" is
//! true and says nothing about what the seventeen dwords *were*. The title
//! submitted something; no counter in the subsystem can say what.
//!
//! So this finds the written region and prints it. Seventeen dwords is small
//! enough to read, and reading it is the difference between "the producer
//! submitted a batch we cannot classify" and knowing whether it set a register,
//! initialised the micro-engine, or wrote a packet with a length that made the
//! command processor skip the rest.
//!
//! ## Why runs and not a fixed window
//!
//! The written dwords are not necessarily at the ring's origin. A producer that
//! wrapped, or that reserved a span and filled part of it, leaves its data
//! wherever its own pointer was. Dumping a fixed prefix of the ring finds
//! nothing in that case and reports an empty ring — which is exactly the wrong
//! conclusion. Locating the non-zero runs first makes the dump independent of
//! where the producer chose to write.
//!
//! ## What the classification is for
//!
//! A run of dwords that decodes cleanly from its first dword is a batch. One
//! that does not is either data the producer wrote without a header, or a batch
//! starting somewhere the run's first dword is not. The two are different
//! findings — the first says the producer wrote payload it never framed, the
//! second says the framing is offset — and both are invisible in a packet count.

const std = @import("std");
const pm4 = @import("pm4.zig");

/// Non-zero regions retained. A producer that scattered its writes across more
/// regions than this has a different problem, and the count is reported so a
/// truncated list never reads as the whole picture.
pub const max_runs = 8;

/// Dwords printed per run. Enough for the 64-dword reservation a swap uses,
/// bounded so a ring the producer filled cannot turn a checkpoint into a log
/// flood.
pub const max_dump_dwords = 64;

/// A contiguous span of dwords that is not all zero.
pub const Run = struct {
    /// Dword index into the ring.
    start: u32 = 0,
    length: u32 = 0,
    /// Whether the run's first dword decodes as a packet whose declared length
    /// fits inside the run. Weak on its own and informative in aggregate: a
    /// producer that framed its batch has this true for its first run.
    frames_cleanly: bool = false,
    first_header: ?pm4.Header = null,
};

pub const Digest = struct {
    runs: [max_runs]Run = [_]Run{.{}} ** max_runs,
    run_count: u32 = 0,
    /// Runs beyond the retained list.
    runs_dropped: u32 = 0,
    nonzero_dwords: u32 = 0,
    scanned_dwords: u32 = 0,
    /// Packets counted excluding the ones a zero dword manufactures. This is
    /// the number a reader wants and the one a naive walk cannot produce.
    real_packets: u32 = 0,
    draws: u32 = 0,
    swaps: u32 = 0,

    pub fn empty(self: Digest) bool {
        return self.nonzero_dwords == 0;
    }

    /// One sentence naming what the producer wrote. Every branch is a different
    /// owner and a different next step.
    pub fn verdict(self: Digest) []const u8 {
        if (self.empty())
            return "not one dword in the ring is non-zero. The producer has never written a command into it, whatever any write-pointer counter says";
        if (self.swaps != 0)
            return "the producer wrote a swap packet. Everything still missing is downstream of the producer";
        if (self.draws != 0)
            return "the producer wrote draws and no swap: it rendered and did not present";
        if (self.real_packets == 0)
            return "the ring holds non-zero dwords and none of them frames as a packet. The producer wrote payload it never gave a header, or wrote at an offset the walk does not start from — either way the command processor reading from the ring's origin would find no work here, and that is a framing defect rather than an absent producer";
        return "the producer wrote framed packets that are neither draws nor a swap: it programmed state and stopped before rendering. The next question is what the title does between this batch and its first draw";
    }
};

fn readDwordBig(bytes: []const u8, index: usize) u32 {
    return std.mem.readInt(u32, bytes[index * 4 ..][0..4], .big);
}

/// Find the non-zero regions of a ring and describe them.
///
/// `limit_dwords` bounds the walk; the caller supplies it so a large ring
/// cannot make a checkpoint diagnostic the dominant cost of the run.
pub fn digest(bytes: []const u8, ring_dwords: u32, limit_dwords: u32) Digest {
    var result = Digest{};
    if (ring_dwords == 0 or bytes.len < @as(usize, ring_dwords) * 4) return result;
    const limit = @min(ring_dwords, limit_dwords);
    result.scanned_dwords = limit;

    var index: u32 = 0;
    while (index < limit) {
        if (readDwordBig(bytes, index) == 0) {
            index += 1;
            continue;
        }
        const start = index;
        while (index < limit and readDwordBig(bytes, index) != 0) : (index += 1) {
            result.nonzero_dwords += 1;
        }
        var run = Run{ .start = start, .length = index - start };
        const header = pm4.decodeHeader(readDwordBig(bytes, start));
        run.first_header = header;
        run.frames_cleanly = header.kind != .type2 and header.totalDwords() <= run.length;
        if (result.run_count < max_runs) {
            result.runs[result.run_count] = run;
            result.run_count += 1;
        } else {
            result.runs_dropped += 1;
        }
    }

    // Packets counted only inside written runs, which is what excludes the
    // thousands a zero-filled ring manufactures.
    var run_index: u32 = 0;
    while (run_index < result.run_count) : (run_index += 1) {
        const run = result.runs[run_index];
        var at: u32 = 0;
        while (at < run.length) {
            const header = pm4.decodeHeader(readDwordBig(bytes, run.start + at));
            const total = header.totalDwords();
            if (header.kind != .type2) {
                result.real_packets += 1;
                if (header.kind == .type3) {
                    if (header.opcode.isDraw()) result.draws += 1;
                    if (header.opcode == .xe_swap) result.swaps += 1;
                }
            }
            if (total == 0 or at + total > run.length) break;
            at += total;
        }
    }
    return result;
}

/// Copy a run's dwords out for printing. Returns how many were written.
pub fn dumpRun(bytes: []const u8, ring_dwords: u32, run: Run, out: []u32) u32 {
    if (ring_dwords == 0 or bytes.len < @as(usize, ring_dwords) * 4) return 0;
    const count = @min(@min(run.length, @as(u32, @intCast(out.len))), max_dump_dwords);
    var index: u32 = 0;
    while (index < count) : (index += 1) {
        out[index] = readDwordBig(bytes, (run.start + index) % ring_dwords);
    }
    return count;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

fn ringImage(comptime dwords: u32, at: u32, values: []const u32) [dwords * 4]u8 {
    var bytes = [_]u8{0} ** (dwords * 4);
    for (values, 0..) |value, index| {
        std.mem.writeInt(u32, bytes[(at + index) * 4 ..][0..4], value, .big);
    }
    return bytes;
}

test "an untouched ring reports no runs rather than thousands of packets" {
    const bytes = ringImage(256, 0, &.{});
    const result = digest(&bytes, 256, 256);
    try std.testing.expect(result.empty());
    try std.testing.expectEqual(@as(u32, 0), result.run_count);
    // The artifact this module exists to remove: a zero dword is a valid
    // type-0 header, so a naive walk reports a full ring of packets.
    try std.testing.expectEqual(@as(u32, 0), result.real_packets);
    try std.testing.expect(std.mem.indexOf(u8, result.verdict(), "never written a command") != null);
}

// The observed run: seventeen non-zero dwords in eight thousand.
test "a small written region in a large ring is found wherever it sits" {
    const bytes = ringImage(8192, 4000, &.{
        pm4.packetType0(0x2000, 3, false).?, 0x1111_1111, 0x2222_2222, 0x3333_3333,
    });
    const result = digest(&bytes, 8192, 8192);
    try std.testing.expectEqual(@as(u32, 1), result.run_count);
    try std.testing.expectEqual(@as(u32, 4000), result.runs[0].start);
    try std.testing.expectEqual(@as(u32, 4), result.runs[0].length);
    try std.testing.expectEqual(@as(u32, 4), result.nonzero_dwords);
    try std.testing.expect(result.runs[0].frames_cleanly);
    try std.testing.expectEqual(@as(u32, 1), result.real_packets);
}

// A producer that wrote payload without framing it looks identical, through a
// packet count, to one that wrote nothing at all.
test "unframed payload is a framing defect rather than an absent producer" {
    // Type-2 fillers only: non-zero, and not a packet anyone will execute.
    const bytes = ringImage(256, 8, &.{
        pm4.packetType2(), pm4.packetType2(), pm4.packetType2(),
    });
    const result = digest(&bytes, 256, 256);
    try std.testing.expect(!result.empty());
    try std.testing.expectEqual(@as(u32, 3), result.nonzero_dwords);
    try std.testing.expectEqual(@as(u32, 0), result.real_packets);
    try std.testing.expect(std.mem.indexOf(u8, result.verdict(), "framing defect") != null);
}

test "a batch of state without draws is distinguished from one with them" {
    const state = ringImage(256, 0, &.{
        pm4.packetType3(.set_constant, 2, false).?, 0x1, 0x2,
        pm4.packetType3(.invalidate_state, 1, false).?, 0x3,
    });
    const state_digest = digest(&state, 256, 256);
    try std.testing.expectEqual(@as(u32, 2), state_digest.real_packets);
    try std.testing.expectEqual(@as(u32, 0), state_digest.draws);
    try std.testing.expect(std.mem.indexOf(u8, state_digest.verdict(), "before rendering") != null);

    const drew = ringImage(256, 0, &.{
        pm4.packetType3(.draw_indx_2, 2, false).?, 0x1, 0x2,
    });
    try std.testing.expectEqual(@as(u32, 1), digest(&drew, 256, 256).draws);
    try std.testing.expect(std.mem.indexOf(u8, digest(&drew, 256, 256).verdict(), "did not present") != null);
}

test "a swap in the payload outranks every other classification" {
    var dwords: [12]u32 = undefined;
    _ = pm4.encodeSwapSequence(&dwords, .{}, .{
        .frontbuffer_physical_address = 0x1FC0_0000,
        .width = 1280,
        .height = 720,
    }, 12).?;
    // Only the first twelve dwords are non-zero; the fill is type-2.
    const bytes = ringImage(256, 0, dwords[0..12]);
    const result = digest(&bytes, 256, 256);
    try std.testing.expectEqual(@as(u32, 1), result.swaps);
    try std.testing.expect(std.mem.indexOf(u8, result.verdict(), "downstream of the producer") != null);
}

test "separate written regions are reported separately" {
    var bytes = [_]u8{0} ** (256 * 4);
    std.mem.writeInt(u32, bytes[10 * 4 ..][0..4], 0xAAAA_AAAA, .big);
    std.mem.writeInt(u32, bytes[50 * 4 ..][0..4], 0xBBBB_BBBB, .big);
    std.mem.writeInt(u32, bytes[51 * 4 ..][0..4], 0xCCCC_CCCC, .big);
    const result = digest(&bytes, 256, 256);
    try std.testing.expectEqual(@as(u32, 2), result.run_count);
    try std.testing.expectEqual(@as(u32, 10), result.runs[0].start);
    try std.testing.expectEqual(@as(u32, 1), result.runs[0].length);
    try std.testing.expectEqual(@as(u32, 50), result.runs[1].start);
    try std.testing.expectEqual(@as(u32, 2), result.runs[1].length);
    try std.testing.expectEqual(@as(u32, 3), result.nonzero_dwords);
}

// A truncated list that did not say it was truncated would read as the whole
// picture.
test "regions past the retained list are counted rather than dropped silently" {
    var bytes = [_]u8{0} ** (256 * 4);
    var index: u32 = 0;
    while (index < max_runs + 4) : (index += 1) {
        std.mem.writeInt(u32, bytes[(index * 2) * 4 ..][0..4], 0x1000_0000 + index, .big);
    }
    const result = digest(&bytes, 256, 256);
    try std.testing.expectEqual(@as(u32, max_runs), result.run_count);
    try std.testing.expectEqual(@as(u32, 4), result.runs_dropped);
    try std.testing.expectEqual(@as(u32, max_runs + 4), result.nonzero_dwords);
}

test "a dump returns the dwords a reader would have to see to judge the batch" {
    const bytes = ringImage(256, 3, &.{ 0x11111111, 0x22222222, 0x33333333 });
    const result = digest(&bytes, 256, 256);
    var out: [max_dump_dwords]u32 = undefined;
    const count = dumpRun(&bytes, 256, result.runs[0], &out);
    try std.testing.expectEqual(@as(u32, 3), count);
    try std.testing.expectEqual(@as(u32, 0x11111111), out[0]);
    try std.testing.expectEqual(@as(u32, 0x33333333), out[2]);
}

test "the dump is bounded so a filled ring cannot flood a checkpoint" {
    var bytes = [_]u8{0} ** (1024 * 4);
    for (0..1024) |index| {
        std.mem.writeInt(u32, bytes[index * 4 ..][0..4], @intCast(index + 1), .big);
    }
    const result = digest(&bytes, 1024, 1024);
    try std.testing.expectEqual(@as(u32, 1), result.run_count);
    var out: [max_dump_dwords]u32 = undefined;
    try std.testing.expectEqual(max_dump_dwords, dumpRun(&bytes, 1024, result.runs[0], &out));
}

test "the walk is bounded independently of the ring's size" {
    var bytes = [_]u8{0} ** (1024 * 4);
    std.mem.writeInt(u32, bytes[900 * 4 ..][0..4], 0xFEED_FACE, .big);
    const bounded = digest(&bytes, 1024, 128);
    try std.testing.expectEqual(@as(u32, 128), bounded.scanned_dwords);
    try std.testing.expect(bounded.empty());

    const full = digest(&bytes, 1024, 1024);
    try std.testing.expectEqual(@as(u32, 1), full.nonzero_dwords);
}

test "a ring shorter than its claimed size is refused rather than read out of bounds" {
    const bytes = [_]u8{0} ** 16;
    const result = digest(&bytes, 256, 256);
    try std.testing.expectEqual(@as(u32, 0), result.scanned_dwords);
    var out: [4]u32 = undefined;
    try std.testing.expectEqual(@as(u32, 0), dumpRun(&bytes, 256, .{ .start = 0, .length = 4 }, &out));
}
