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
    /// Every retained non-zero run was framed from its first dword through its
    /// end. This is stream evidence, not XE_SWAP evidence.
    stream_validated: bool = false,

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
    var all_runs_clean = result.run_count != 0 and result.runs_dropped == 0;
    var run_index: u32 = 0;
    while (run_index < result.run_count) : (run_index += 1) {
        const run = result.runs[run_index];
        if (!run.frames_cleanly) all_runs_clean = false;
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
            if (total == 0 or at + total > run.length) {
                all_runs_clean = false;
                break;
            }
            at += total;
        }
        if (at != run.length) all_runs_clean = false;
    }
    result.stream_validated = all_runs_clean and result.real_packets != 0;
    return result;
}

/// The window a command processor should be handed for a retained batch, as
/// distinct from the window the batch's non-zero content occupies.
///
/// ## Why the two differ
///
/// `digest` finds runs of non-zero dwords, which is the right shape for saying
/// what the producer wrote. It is the wrong shape for handing to a decoder: a
/// PM4 packet's payload may legitimately contain a zero dword, so a
/// content-derived envelope can end *in the middle of a packet*. The decoder
/// then reads a header that declares more dwords than the window holds and
/// refuses the whole batch — and on 2026-09-01 that is exactly what happened:
/// a fourteen-dword envelope, `error=TruncatedRing`, and every render-target
/// stage below the stateful executor reading zero for the rest of the run
/// because the only thing that could have programmed them was thrown away.
///
/// So the extent is derived from the *frames*: start where the content starts,
/// and end after the last packet whose header begins inside the content
/// envelope. Nothing here reads or interprets payload — it walks headers.
pub const FramedExtent = struct {
    start: u32 = 0,
    /// Dwords from `start`, covering whole packets.
    dwords: u32 = 0,
    /// Packet headers crossed. Zero means nothing in the envelope framed.
    packets: u32 = 0,
    /// A header began inside the envelope and its packet ends past the content
    /// the envelope described. This is the case the content window cuts in
    /// half, and a non-zero count is the reason the two numbers differ.
    packets_beyond_content: u32 = 0,
    /// A header began inside the envelope and its payload runs past the end of
    /// the ring. The extent stops there and the batch really is truncated.
    truncated_by_ring: bool = false,
    /// The walk stopped on a header that declares no length. Nothing after it
    /// can be framed from here.
    stopped_at_unframed_dword: bool = false,
    /// The walk hit its iteration bound before running out of packets.
    stopped_at_limit: bool = false,

    /// Whether the frame-derived window is wider than the content-derived one.
    pub fn widensContentWindow(self: FramedExtent) bool {
        return self.packets_beyond_content != 0;
    }
};

/// Extend a content envelope to whole packets.
///
/// `envelope_dwords` is the content window (the digest's run envelope) and
/// bounds which headers are considered: a packet is included when its *header*
/// begins inside it. `limit_dwords` bounds the walk itself so a malformed ring
/// cannot make this the dominant cost of a checkpoint.
pub fn framedExtent(
    bytes: []const u8,
    ring_dwords: u32,
    start: u32,
    envelope_dwords: u32,
    limit_dwords: u32,
) FramedExtent {
    var result = FramedExtent{ .start = start };
    if (ring_dwords == 0 or envelope_dwords == 0) return result;
    if (start >= ring_dwords) return result;
    if (bytes.len < @as(usize, ring_dwords) * 4) return result;

    const content_end = @min(start +| envelope_dwords, ring_dwords);
    var at: u32 = start;
    var steps: u32 = 0;
    while (at < content_end) {
        if (steps >= limit_dwords) {
            result.stopped_at_limit = true;
            break;
        }
        steps += 1;
        const raw = readDwordBig(bytes, at);
        // A zero dword is never a header. `decodeHeader` reads it as a
        // two-dword type-0 packet, which is exactly the phantom packet the
        // digest above excludes, and walking it would extend the window
        // through untouched ring.
        if (raw == 0) {
            result.stopped_at_unframed_dword = true;
            break;
        }
        const header = pm4.decodeHeader(raw);
        const total = header.totalDwords();
        if (total == 0) {
            result.stopped_at_unframed_dword = true;
            break;
        }
        const end = at +| total;
        if (end > ring_dwords) {
            result.truncated_by_ring = true;
            break;
        }
        result.packets += 1;
        if (end > content_end) result.packets_beyond_content += 1;
        result.dwords = end - start;
        at = end;
    }
    // Never narrower than the content the caller already knew about: a walk
    // that framed nothing must not shrink the window and turn a decodable
    // batch into an empty one.
    if (result.dwords < @min(envelope_dwords, ring_dwords - start)) {
        result.dwords = @min(envelope_dwords, ring_dwords - start);
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
        pm4.packetType3(.set_constant, 2, false).?,     0x1, 0x2,
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

// The 2026-09-01 defect, reproduced. A packet whose payload contains a zero
// dword splits the non-zero run, the content envelope ends inside the packet,
// and the decoder handed that envelope refuses the entire batch.
test "a packet whose payload holds a zero dword still frames completely" {
    var bytes = [_]u8{0} ** (64 * 4);
    // TYPE3 packet at dword 0 declaring six payload dwords, one of which is
    // zero. The content run therefore ends at dword 5, mid-packet.
    const header = pm4.packetType3(.set_constant, 6, false).?;
    std.mem.writeInt(u32, bytes[0..4], header, .big);
    for (1..7) |index| {
        const value: u32 = if (index == 5) 0 else 0x1000 + @as(u32, @intCast(index));
        std.mem.writeInt(u32, bytes[index * 4 ..][0..4], value, .big);
    }

    const content = digest(&bytes, 64, 64);
    try std.testing.expect(content.run_count >= 1);
    try std.testing.expectEqual(@as(u32, 0), content.runs[0].start);
    // The content window is short: it stops at the zero dword inside the
    // payload, which is the whole problem.
    try std.testing.expect(content.runs[0].length < 7);

    const framed = framedExtent(&bytes, 64, 0, content.runs[0].length, 64);
    try std.testing.expectEqual(@as(u32, 7), framed.dwords);
    try std.testing.expectEqual(@as(u32, 1), framed.packets);
    try std.testing.expectEqual(@as(u32, 1), framed.packets_beyond_content);
    try std.testing.expect(framed.widensContentWindow());
    try std.testing.expect(!framed.truncated_by_ring);
}

// A batch that frames cleanly inside its content must not be widened: the
// extent is a repair for a specific defect, not a licence to hand the decoder
// dwords the producer never wrote.
test "a cleanly framed batch is not widened" {
    var bytes = [_]u8{0} ** (64 * 4);
    const header = pm4.packetType3(.set_constant, 2, false).?;
    std.mem.writeInt(u32, bytes[0..4], header, .big);
    std.mem.writeInt(u32, bytes[4..8], 0x1111, .big);
    std.mem.writeInt(u32, bytes[8..12], 0x2222, .big);

    const content = digest(&bytes, 64, 64);
    try std.testing.expectEqual(@as(u32, 3), content.runs[0].length);
    const framed = framedExtent(&bytes, 64, 0, 3, 64);
    try std.testing.expectEqual(@as(u32, 3), framed.dwords);
    try std.testing.expectEqual(@as(u32, 0), framed.packets_beyond_content);
    try std.testing.expect(!framed.widensContentWindow());
}

// A header whose payload genuinely runs past the ring is truncated, and saying
// so is the difference between a windowing repair and a claim about the ring.
test "a packet that runs past the ring end is reported as truncated" {
    var bytes = [_]u8{0} ** (8 * 4);
    const header = pm4.packetType3(.set_constant, 32, false).?;
    std.mem.writeInt(u32, bytes[0..4], header, .big);
    std.mem.writeInt(u32, bytes[4..8], 0x1234, .big);

    const framed = framedExtent(&bytes, 8, 0, 2, 64);
    try std.testing.expect(framed.truncated_by_ring);
    try std.testing.expectEqual(@as(u32, 0), framed.packets);
    // Never narrower than what the caller already had.
    try std.testing.expectEqual(@as(u32, 2), framed.dwords);
}

// The walk is bounded and every degenerate shape has to terminate, or a
// malformed ring turns a checkpoint into the run.
test "the framed extent terminates on filler, on a bound and outside the ring" {
    var bytes = [_]u8{0} ** (32 * 4);
    // All zero: no frame at all, and the window stays what it was.
    const empty = framedExtent(&bytes, 32, 0, 4, 64);
    try std.testing.expectEqual(@as(u32, 4), empty.dwords);
    try std.testing.expectEqual(@as(u32, 0), empty.packets);

    // A start past the ring answers nothing rather than reading out of bounds.
    const outside = framedExtent(&bytes, 32, 64, 4, 64);
    try std.testing.expectEqual(@as(u32, 0), outside.dwords);

    // An empty envelope is not a window.
    try std.testing.expectEqual(@as(u32, 0), framedExtent(&bytes, 32, 0, 0, 64).dwords);

    // A wall of one-dword type-2 filler against a tight iteration bound stops
    // at the bound and says so.
    for (0..32) |index| {
        std.mem.writeInt(u32, bytes[index * 4 ..][0..4], @as(u32, 2) << 30, .big);
    }
    const bounded = framedExtent(&bytes, 32, 0, 32, 4);
    try std.testing.expect(bounded.stopped_at_limit);
    try std.testing.expect(bounded.packets <= 4);
}
