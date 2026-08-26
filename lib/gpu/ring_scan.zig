//! What is actually in the guest's ring buffer.
//!
//! Every counter in the graphics stack describes the ring indirectly. "The
//! guest published 25 dwords." "The command processor consumed 22." "No swap
//! packet was decoded." Each of those is a number produced by something that
//! read the ring and then threw the contents away, and together they still do
//! not answer the only question that matters when a title stops submitting:
//! *what did it submit?*
//!
//! Twenty-five dwords is either a title that set some state and stopped, or a
//! title that drew a frame and never presented it, or a title that wrote one
//! malformed packet the command processor skipped. Those are three different
//! bugs with three different owners, and no dword count can tell them apart.
//! This module reads the span and says which one it is.
//!
//! ## Why the guest's ring is readable at all
//!
//! The ring lives in the emulated console's physical memory, which lives inside
//! the emulator's address space, which is Rosette's guest memory. Two
//! translations, both already modelled: `xenia_memory_views` resolves a console
//! physical address to the host address the translated stores actually use, and
//! Rosette's own memory accessor resolves that. So the ring is ordinary memory
//! to a harness — no emulator cooperation, no log parsing, no new plumbing.
//!
//! Dwords in it are big-endian, because the console is. Reading them natively
//! is the mistake that makes every packet decode as an unknown opcode, so the
//! byte swap happens here, once, at the boundary.
//!
//! ## What this deliberately does not do
//!
//! It does not write. Publishing into the ring is a separate capability with a
//! separate owner question (`ring_injection.zig`), and mixing "look at what the
//! guest did" with "do something the guest did not" in one module is how an
//! observation quietly becomes an intervention.

const std = @import("std");
const pm4 = @import("pm4.zig");

/// The most dwords one scan will walk. The ring can be megabytes; a scan is a
/// diagnostic that runs on a heartbeat, and an unbounded walk over a ring the
/// producer is concurrently writing is both slow and unrepeatable.
pub const max_scan_dwords: u32 = 4096;

/// The most dwords a whole-ring signature search will examine. Larger than the
/// span cap because the search is a single comparison per dword and the packet
/// it is looking for can be anywhere the producer put it.
pub const max_search_dwords: u32 = 262_144;

/// What a scan found, in the order a reader needs it.
pub const Summary = struct {
    /// Dwords the packet walk consumed. Less than `dwords_examined` when the
    /// walk stopped early on a truncated or malformed packet.
    dwords_scanned: u32 = 0,
    /// Dwords looked at at all: the span, capped. The denominator for "how much
    /// of what the producer published did the walk actually account for".
    dwords_examined: u32 = 0,
    /// Dwords the span claimed to hold.
    span_dwords: u32 = 0,
    /// Whether the walk ran out of span mid-packet. A truncated tail is normal
    /// while a producer is writing and pathological when the ring is idle, so
    /// the two are told apart by whether anything else is moving.
    truncated: bool = false,
    /// The walk lost sync: a packet claimed a length that ran past the span.
    /// Distinct from truncation — this one means the dwords are not a packet
    /// stream at the offset the reader started from.
    desynchronised: bool = false,
    /// A packet header or payload failed a strict PM4/XE_SWAP check.  Unknown
    /// opcodes are not counted here: they are valid type-3 packets that this
    /// observer does not interpret, while a malformed XE_SWAP is evidence
    /// against the VdSwap handoff itself.
    malformed_packets: u32 = 0,

    packets: u32 = 0,
    type0_packets: u32 = 0,
    type2_fillers: u32 = 0,
    type3_packets: u32 = 0,
    draw_packets: u32 = 0,
    swap_packets: u32 = 0,
    /// XE_SWAP headers found, including candidates whose payload is truncated
    /// or whose signature/shape fails strict decoding.
    swap_candidates: u32 = 0,
    /// Candidates for which the complete five-dword packet payload was within
    /// the observed span. This says nothing about its signature.
    swap_payload_readable: u32 = 0,
    swap_malformed_candidates: u32 = 0,
    swap_truncated_candidates: u32 = 0,
    /// Dwords that were zero rather than a packet. A ring nobody has written
    /// reads as zeros, and zero decodes as a type-0 write of one dword to
    /// register zero — a real-looking packet that never existed.
    zero_dwords: u32 = 0,

    /// The swap, if the span holds one. This is the fact the whole graphics
    /// ladder turns on, so it is returned rather than counted.
    swap: ?pm4.SwapDescription = null,
    /// Dword offset of the first XE_SWAP header in the ring.  This remains
    /// useful when the payload is malformed: the failure report can name the
    /// exact candidate instead of only saying that a swap was absent.
    swap_offset: ?u32 = null,
    /// The texture fetch constant the swap packet was preceded by. The swap
    /// itself carries only an address and an extent; tiling, byte order and
    /// pixel format live here, and without them the front buffer converts into
    /// a sheared or colour-swapped picture rather than into a failure.
    fetch: ?pm4.FetchConstant = null,

    /// The first type-3 opcode seen, which is usually what the title was doing.
    first_opcode: ?pm4.Type3Opcode = null,
    last_opcode: ?pm4.Type3Opcode = null,

    /// Whether the span is entirely no-ops and zeros: allocated, never used.
    pub fn empty(self: Summary) bool {
        return self.type0_packets == 0 and self.type3_packets == 0;
    }

    /// One sentence naming what the span is, because the counts above are the
    /// evidence and this is the finding. Written as a claim a reader can act
    /// on rather than a restatement of the numbers.
    pub fn verdict(self: Summary) []const u8 {
        if (self.desynchronised)
            return "the dwords at the read offset are not a packet stream: a packet claimed a length that overran the span. Either the offset is wrong or the producer wrote a malformed header, and the command processor would have skipped or mis-decoded exactly the same way";
        if (self.dwords_scanned == 0 and self.dwords_examined == 0)
            return "the span is empty: the read and write pointers agree, so the producer has published nothing that the command processor has not already drained";
        // Against the examined count, not the walked one: the walk steps two
        // dwords per zero, so an odd run of zeros ends truncated and leaves the
        // two counts one apart on the exact case this line has to catch.
        if (self.dwords_examined != 0 and self.zero_dwords == self.dwords_examined)
            return "every dword in the span is zero: the ring is allocated and nothing has ever been written into it. This is a producer that never ran, not a consumer that failed to drain";
        if (self.empty())
            return "the span holds only filler: the ring was published with no commands in it, which is a producer that advanced the write pointer without writing a batch";
        if (self.swap != null)
            return "the span contains an XE_SWAP packet: the title asked to present, so anything still missing downstream is the command processor's or the presenter's";
        if (self.swap_candidates != 0)
            return "the span contains XE_SWAP candidate headers, but none passed strict payload decoding. The producer reached the handoff shape and the failure is in packet extent, signature or publication stability";
        if (self.draw_packets != 0)
            return "the span contains draws and no swap: the title rendered and did not present. The frontier is whatever the title does between its last draw and its present call, not the GPU path";
        return "the span contains state and no draws: the title programmed the GPU and never asked it to render, so it has not reached its rendering path at all";
    }
};

/// Byte-swapped dword read. The ring is console memory and the console is
/// big-endian; this is the single place that matters.
fn readDwordBig(bytes: []const u8, index: usize) u32 {
    const at = index * 4;
    return std.mem.readInt(u32, bytes[at..][0..4], .big);
}

/// Walk a dword span of ring memory and describe it.
///
/// `bytes` is the whole ring, `start_dword` and `count_dwords` the span the
/// pointers describe. The span is walked with wrapping, because a write pointer
/// behind a read pointer has wrapped the ring rather than gone backwards, and a
/// scan that stops at the end of the buffer misses exactly the frame that
/// straddled it.
pub fn scan(bytes: []const u8, start_dword: u32, count_dwords: u32, ring_dwords: u32) Summary {
    var summary = Summary{ .span_dwords = count_dwords };
    if (ring_dwords == 0 or bytes.len < @as(usize, ring_dwords) * 4) return summary;
    if (count_dwords == 0) return summary;

    const limit = @min(count_dwords, max_scan_dwords);

    // Counted in its own pass rather than inside the walk. A zero dword is a
    // valid type-0 header claiming one payload dword, so the walk steps over
    // two dwords for every zero it meets and would report a ring of zeros as
    // half zeros — the one case where the count has to be exact, because
    // "every dword is zero" is the verdict that says the producer never ran.
    summary.dwords_examined = limit;
    var probe: u32 = 0;
    while (probe < limit) : (probe += 1) {
        if (readDwordBig(bytes, (start_dword + probe) % ring_dwords) == 0) summary.zero_dwords += 1;
    }

    var scratch: [16]u32 = undefined;
    var offset: u32 = 0;
    while (offset < limit) {
        const raw = readDwordBig(bytes, (start_dword + offset) % ring_dwords);
        const header = pm4.decodeHeader(raw);
        const total = header.totalDwords();

        // Inspect XE_SWAP before applying the generic stream-boundary check.
        // A candidate at the end of the published span is the evidence we
        // need most: the producer named the handoff, but publication exposed
        // only part of its five-dword payload.
        if (header.kind == .type3 and header.opcode == .xe_swap) {
            summary.swap_candidates += 1;
            summary.swap_packets += 1;
            if (summary.swap_offset == null) {
                summary.swap_offset = (start_dword + offset) % ring_dwords;
            }
            if (offset + 5 > limit) {
                summary.swap_truncated_candidates += 1;
            } else {
                summary.swap_payload_readable += 1;
                var index: u32 = 0;
                while (index < 5) : (index += 1) {
                    scratch[index] = readDwordBig(bytes, (start_dword + offset + index) % ring_dwords);
                }
                if (header.count != 4) {
                    summary.swap_malformed_candidates += 1;
                    summary.malformed_packets += 1;
                } else {
                    const decoded = pm4.decodeSwapSequence(scratch[0..5]);
                    if (decoded) |swap| {
                        if (summary.swap == null) {
                            summary.fetch = readFetchBefore(bytes, start_dword + offset, ring_dwords);
                            summary.swap = swap;
                        }
                    } else {
                        summary.swap_malformed_candidates += 1;
                        summary.malformed_packets += 1;
                    }
                }
            }
        }
        if (offset + total > limit) {
            // Distinguish "the producer is mid-write" from "this is not a
            // packet stream". A packet whose declared length overruns the whole
            // ring cannot be a partial write of a real packet.
            if (total > ring_dwords) summary.desynchronised = true else summary.truncated = true;
            break;
        }
        summary.packets += 1;
        switch (header.kind) {
            .type0 => summary.type0_packets += 1,
            .type1 => {},
            .type2 => summary.type2_fillers += 1,
            .type3 => {
                summary.type3_packets += 1;
                if (summary.first_opcode == null) summary.first_opcode = header.opcode;
                summary.last_opcode = header.opcode;
                if (header.opcode.isDraw()) summary.draw_packets += 1;
            },
        }
        offset += total;
    }
    summary.dwords_scanned = offset;
    return summary;
}

/// The six-dword texture fetch constant immediately before a swap header.
///
/// `VdSwap` writes a type-0 register write of six dwords and then the swap, so
/// the fetch sits at exactly `header - 7`. Verified by decoding that dword as a
/// type-0 packet targeting the fetch register rather than assumed from the
/// offset: the ring holds stale data, and seven dwords back from any header is
/// always *something*.
fn readFetchBefore(bytes: []const u8, swap_header_dword: u32, ring_dwords: u32) ?pm4.FetchConstant {
    if (ring_dwords < 8) return null;
    const header_index = (swap_header_dword + ring_dwords - 7) % ring_dwords;
    const header = pm4.decodeHeader(readDwordBig(bytes, header_index));
    if (header.kind != .type0) return null;
    if (header.register_index != pm4.shader_constant_fetch_00_0) return null;
    if (header.count < 6) return null;
    var fetch = pm4.FetchConstant{};
    for (&fetch.dwords, 0..) |*dword, offset| {
        dword.* = readDwordBig(bytes, (header_index + 1 + offset) % ring_dwords);
    }
    return fetch;
}

/// A swap found in the ring, with the fetch constant that described its surface.
pub const FoundSwap = struct {
    swap: pm4.SwapDescription,
    fetch: ?pm4.FetchConstant = null,
    /// Header dword offset in the ring, not the signature payload offset.
    offset: u32,
};

/// Evidence from a bounded whole-ring search. Unlike `findAnySwap`, this keeps
/// malformed and incomplete XE_SWAP candidates instead of collapsing them into
/// "no swap". That distinction is what lets the contract separate a producer
/// that never wrote the handoff from one that wrote a handoff the consumer
/// could not decode.
pub const SwapEvidence = struct {
    candidates: u32 = 0,
    payload_readable: u32 = 0,
    decoded: u32 = 0,
    malformed: u32 = 0,
    truncated: u32 = 0,
    first_offset: ?u32 = null,
    first_decoded: ?FoundSwap = null,
};

/// Search the retained ring image for XE_SWAP headers and retain every useful
/// boundary fact. The ring image is complete, so a candidate's five dwords can
/// wrap from the final slot back to slot zero; a candidate is "truncated" here
/// only when the image itself is too small to hold a packet.
pub fn findSwapEvidence(bytes: []const u8, ring_dwords: u32) SwapEvidence {
    var evidence = SwapEvidence{};
    if (ring_dwords < 5 or bytes.len < @as(usize, ring_dwords) * 4) return evidence;
    const limit = @min(ring_dwords, max_search_dwords);
    if (limit == 0) return evidence;

    var scratch: [5]u32 = undefined;
    var index: u32 = 0;
    while (index < limit) : (index += 1) {
        const header = pm4.decodeHeader(readDwordBig(bytes, index));
        if (header.kind != .type3 or header.opcode != .xe_swap) continue;

        evidence.candidates += 1;
        if (evidence.first_offset == null) evidence.first_offset = index;
        evidence.payload_readable += 1;
        var payload_index: u32 = 0;
        while (payload_index < 5) : (payload_index += 1) {
            scratch[payload_index] = readDwordBig(bytes, (index + payload_index) % ring_dwords);
        }
        if (header.count != 4) {
            evidence.malformed += 1;
        } else {
            const swap = pm4.decodeSwapSequence(scratch[0..]);
            if (swap) |description| {
                evidence.decoded += 1;
                if (evidence.first_decoded == null) {
                    evidence.first_decoded = .{
                        .swap = description,
                        .fetch = readFetchBefore(bytes, index, ring_dwords),
                        .offset = index,
                    };
                }
            } else {
                evidence.malformed += 1;
            }
        }
    }
    return evidence;
}

/// Count draw packets anywhere in the ring, ignoring the pointers.
///
/// The pointers describe what is outstanding, and a drained ring holds an empty
/// span — so a title that rendered a frame and had it consumed looks, through
/// the pointers alone, exactly like a title that never drew. Those are opposite
/// findings, and the dwords are still there.
///
/// Walked from the ring's own origin rather than from the read pointer: a
/// consumed batch starts wherever the producer put it, and the origin is the
/// only offset that is not itself a guess. A stale ring can desynchronise the
/// walk, so this reports a count and never a "no draws" claim — absence here is
/// weak evidence and presence is strong.
pub fn countDraws(bytes: []const u8, ring_dwords: u32) u32 {
    if (ring_dwords == 0 or bytes.len < @as(usize, ring_dwords) * 4) return 0;
    const limit = @min(ring_dwords, max_scan_dwords);
    var draws: u32 = 0;
    var index: u32 = 0;
    while (index < limit) {
        const header = pm4.decodeHeader(readDwordBig(bytes, index));
        if (header.kind == .type3 and header.opcode.isDraw()) draws += 1;
        const advance = header.totalDwords();
        if (advance == 0 or index + advance > limit) break;
        index += advance;
    }
    return draws;
}

/// Search the whole ring for a swap, ignoring the pointers.
///
/// The pointers describe what is *outstanding*. A swap the command processor
/// already consumed leaves its dwords in the ring until something overwrites
/// them, so this answers a different and often more useful question: has this
/// title ever written a swap packet at all? A yes here with a zero swap counter
/// upstream means the packet was written and not decoded, which is a completely
/// different bug from a packet that was never written.
pub fn findAnySwap(bytes: []const u8, ring_dwords: u32) ?FoundSwap {
    return findSwapEvidence(bytes, ring_dwords).first_decoded;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

/// Build a big-endian ring image from dwords, the way guest memory holds them.
fn ringImage(comptime dwords: u32, values: []const u32) [dwords * 4]u8 {
    var bytes = [_]u8{0} ** (dwords * 4);
    for (values, 0..) |value, index| {
        std.mem.writeInt(u32, bytes[index * 4 ..][0..4], value, .big);
    }
    return bytes;
}

test "a span of zeros is reported as a ring nobody ever wrote" {
    const bytes = ringImage(64, &.{});
    const summary = scan(&bytes, 0, 32, 64);
    try std.testing.expectEqual(@as(u32, 32), summary.zero_dwords);
    try std.testing.expect(std.mem.indexOf(u8, summary.verdict(), "never ran") != null);
}

// The distinction the whole module exists for: a dword count cannot tell a
// title that drew from a title that only set state, and those have different
// owners.
test "state without draws and draws without a swap are different findings" {
    const state = ringImage(64, &.{
        pm4.packetType3(.set_constant, 2, false).?,     0, 0,
        pm4.packetType3(.invalidate_state, 1, false).?, 0,
    });
    const state_summary = scan(&state, 0, 5, 64);
    try std.testing.expectEqual(@as(u32, 0), state_summary.draw_packets);
    try std.testing.expect(std.mem.indexOf(u8, state_summary.verdict(), "never asked it to render") != null);

    const drew = ringImage(64, &.{
        pm4.packetType3(.set_constant, 2, false).?, 0, 0,
        pm4.packetType3(.draw_indx_2, 2, false).?,  0, 0,
    });
    const drew_summary = scan(&drew, 0, 6, 64);
    try std.testing.expectEqual(@as(u32, 1), drew_summary.draw_packets);
    try std.testing.expect(std.mem.indexOf(u8, drew_summary.verdict(), "did not present") != null);
}

test "a swap in the span is returned rather than counted" {
    var dwords: [12]u32 = undefined;
    var fetch = pm4.FetchConstant{};
    fetch.setBaseAddress(0x1F80_0000);
    fetch.setSize2d(1280, 720);
    _ = pm4.encodeSwapSequence(&dwords, fetch, .{
        .frontbuffer_physical_address = 0x1F80_0000,
        .width = 1280,
        .height = 720,
    }, 12).?;
    const bytes = ringImage(64, &dwords);

    const summary = scan(&bytes, 0, 12, 64);
    try std.testing.expectEqual(@as(u32, 1), summary.swap_packets);
    try std.testing.expectEqual(@as(u32, 7), summary.swap_offset.?);
    try std.testing.expectEqual(@as(u32, 1280), summary.swap.?.width);
    try std.testing.expectEqual(@as(u32, 0x1F80_0000), summary.swap.?.frontbuffer_physical_address);
    try std.testing.expect(std.mem.indexOf(u8, summary.verdict(), "asked to present") != null);
}

// A frame that straddles the end of the ring is exactly the frame a scan that
// stops at the buffer end would miss, and it is not a rare case: the producer
// wraps once per ring's worth of commands.
test "a span that wraps the end of the ring is walked through the wrap" {
    var dwords: [16]u32 = undefined;
    _ = pm4.encodeSwapSequence(&dwords, .{}, .{
        .frontbuffer_physical_address = 0x2000_0000,
        .width = 640,
        .height = 480,
    }, 12).?;

    // Place the packet so it starts four dwords before the end of a 16-dword
    // ring: dwords 12..15 then 0..7.
    var bytes = [_]u8{0} ** 64;
    for (dwords[0..12], 0..) |value, index| {
        const slot = (12 + index) % 16;
        std.mem.writeInt(u32, bytes[slot * 4 ..][0..4], value, .big);
    }
    const summary = scan(&bytes, 12, 12, 16);
    try std.testing.expectEqual(@as(u32, 1), summary.swap_packets);
    try std.testing.expectEqual(@as(u32, 640), summary.swap.?.width);
}

test "a packet claiming more dwords than the ring holds is desynchronisation, not truncation" {
    const bytes = ringImage(64, &.{ pm4.packetType3(.set_constant, 0x4000, false).?, 0, 0, 0 });
    const summary = scan(&bytes, 0, 4, 64);
    try std.testing.expect(summary.desynchronised);
    try std.testing.expect(!summary.truncated);
    try std.testing.expect(std.mem.indexOf(u8, summary.verdict(), "not a packet stream") != null);
}

test "a producer caught mid-write truncates rather than desynchronising" {
    const bytes = ringImage(64, &.{ pm4.packetType3(.set_constant, 8, false).?, 0, 0, 0 });
    const summary = scan(&bytes, 0, 4, 64);
    try std.testing.expect(summary.truncated);
    try std.testing.expect(!summary.desynchronised);
}

test "an empty span says the consumer has drained everything rather than nothing exists" {
    const bytes = ringImage(64, &.{});
    const summary = scan(&bytes, 0, 0, 64);
    try std.testing.expectEqual(@as(u32, 0), summary.dwords_scanned);
    try std.testing.expect(std.mem.indexOf(u8, summary.verdict(), "already drained") != null);
}

// "Has a swap ever been written" and "is a swap outstanding" are different
// questions, and only the first can distinguish a packet that was written and
// not decoded from one that was never written.
test "a consumed swap is still found by a whole-ring search" {
    var dwords: [12]u32 = undefined;
    _ = pm4.encodeSwapSequence(&dwords, .{}, .{
        .frontbuffer_physical_address = 0x1FC0_0000,
        .width = 1152,
        .height = 640,
    }, 12).?;
    const bytes = ringImage(64, &dwords);

    // Nothing is outstanding: the pointers agree.
    try std.testing.expect(scan(&bytes, 0, 0, 64).swap == null);
    const found = findAnySwap(&bytes, 64).?;
    try std.testing.expectEqual(@as(u32, 1152), found.swap.width);
    try std.testing.expectEqual(@as(u32, 0x1FC0_0000), found.swap.frontbuffer_physical_address);
    try std.testing.expectEqual(@as(u32, 7), found.offset);
}

// The swap carries an address and an extent; everything that decides how to
// read the pixels is in the fetch constant seven dwords earlier.
test "the fetch constant preceding a swap is recovered with it" {
    var dwords: [12]u32 = undefined;
    var fetch = pm4.FetchConstant{};
    fetch.setBaseAddress(0x1FC0_0000);
    fetch.setSize2d(1280, 720);
    fetch.setTiled(true);
    fetch.setEndianness(2);
    fetch.setFormat(6);
    _ = pm4.encodeSwapSequence(&dwords, fetch, .{
        .frontbuffer_physical_address = 0x1FC0_0000,
        .width = 1280,
        .height = 720,
    }, 12).?;
    const bytes = ringImage(64, &dwords);

    const found = findAnySwap(&bytes, 64).?;
    try std.testing.expect(found.fetch != null);
    try std.testing.expect(found.fetch.?.tiled());
    try std.testing.expectEqual(@as(u2, 2), found.fetch.?.endianness());
    try std.testing.expectEqual(@as(u32, 0x1FC0_0000), found.fetch.?.baseAddress());
    try std.testing.expectEqual(@as(u32, 1280), found.fetch.?.size2d().width);

    // And through the span walk, which reaches it by a different route.
    const summary = scan(&bytes, 0, 12, 64);
    try std.testing.expect(summary.fetch != null);
    try std.testing.expectEqual(@as(u32, 720), summary.fetch.?.size2d().height);
}

// Seven dwords back from any header is always *something*; only a type-0 write
// to the fetch register is actually a fetch constant.
test "stale dwords before a swap are not mistaken for a fetch constant" {
    var dwords: [12]u32 = undefined;
    _ = pm4.encodeSwapSequence(&dwords, .{}, .{
        .frontbuffer_physical_address = 0x1FC0_0000,
        .width = 640,
        .height = 480,
    }, 12).?;
    // Corrupt the type-0 header so it no longer targets the fetch register.
    dwords[0] = pm4.packetType0(0x2000, 6, false).?;
    const bytes = ringImage(64, &dwords);
    const found = findAnySwap(&bytes, 64).?;
    try std.testing.expectEqual(@as(u32, 640), found.swap.width);
    try std.testing.expect(found.fetch == null);
}

// Texture and vertex data share the ring's memory once the producer wraps, and
// four bytes spelling 'SWAP' in a texture is not improbable over megabytes.
// A drained ring holds an empty span, so a title that drew a frame and had it
// consumed looks through the pointers exactly like one that never drew.
test "draws consumed before the scan are still found in the ring" {
    const bytes = ringImage(64, &.{
        pm4.packetType3(.set_constant, 2, false).?, 0, 0,
        pm4.packetType3(.draw_indx_2, 2, false).?,  0, 0,
        pm4.packetType3(.draw_indx, 1, false).?,    0,
    });
    // Nothing outstanding, and the draws are still there.
    try std.testing.expectEqual(@as(u32, 0), scan(&bytes, 0, 0, 64).draw_packets);
    try std.testing.expectEqual(@as(u32, 2), countDraws(&bytes, 64));
}

test "a bare signature without a swap header is not mistaken for a swap" {
    const bytes = ringImage(64, &.{ 0x11223344, pm4.swap_signature, 0x1000, 640, 480 });
    try std.testing.expect(findAnySwap(&bytes, 64) == null);
}

test "ordinary PM4 never satisfies XE_SWAP candidate evidence" {
    const bytes = ringImage(64, &.{
        pm4.packetType3(.set_constant, 2, false).?, 0x11, 0x22,
        pm4.packetType3(.draw_indx_2, 2, false).?,  0x33, 0x44,
    });
    const summary = scan(&bytes, 0, 6, 64);
    try std.testing.expectEqual(@as(u32, 0), summary.swap_candidates);
    try std.testing.expectEqual(@as(u32, 0), summary.swap_payload_readable);
    try std.testing.expect(summary.swap == null);
}

test "a malformed XE_SWAP candidate is retained as evidence without decoding" {
    const bytes = ringImage(64, &.{
        pm4.packetType3(.xe_swap, 4, false).?, 0x4E4F_5357, 0x1FC0_0000, 1280, 720,
    });
    const summary = scan(&bytes, 0, 5, 64);
    try std.testing.expectEqual(@as(u32, 1), summary.swap_candidates);
    try std.testing.expectEqual(@as(u32, 1), summary.swap_payload_readable);
    try std.testing.expectEqual(@as(u32, 1), summary.swap_malformed_candidates);
    try std.testing.expectEqual(@as(u32, 0), summary.swap_truncated_candidates);
    try std.testing.expect(summary.swap == null);
    try std.testing.expect(std.mem.indexOf(u8, summary.verdict(), "candidate headers") != null);
}

test "a partial XE_SWAP candidate is distinguishable from a malformed payload" {
    const bytes = ringImage(64, &.{
        pm4.packetType3(.xe_swap, 4, false).?, pm4.swap_signature,
    });
    const summary = scan(&bytes, 0, 2, 64);
    try std.testing.expectEqual(@as(u32, 1), summary.swap_candidates);
    try std.testing.expectEqual(@as(u32, 0), summary.swap_payload_readable);
    try std.testing.expectEqual(@as(u32, 1), summary.swap_truncated_candidates);
    try std.testing.expect(summary.swap == null);
}

test "the scan is bounded so a large ring cannot stall the heartbeat" {
    const dwords: u32 = 8192;
    var bytes = std.mem.zeroes([dwords * 4]u8);
    for (0..dwords) |index| {
        std.mem.writeInt(u32, bytes[index * 4 ..][0..4], pm4.packetType2(), .big);
    }
    const summary = scan(&bytes, 0, dwords, dwords);
    try std.testing.expectEqual(max_scan_dwords, summary.dwords_scanned);
    try std.testing.expectEqual(dwords, summary.span_dwords);
}

test "a ring smaller than the bytes claim is refused rather than read out of bounds" {
    const bytes = [_]u8{0} ** 16;
    const summary = scan(&bytes, 0, 8, 64);
    try std.testing.expectEqual(@as(u32, 0), summary.dwords_scanned);
    try std.testing.expect(findAnySwap(&bytes, 64) == null);
}
