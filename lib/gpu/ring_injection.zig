//! Ring injection — Rosette's own synthetic queue, and the only part of the
//! graphics path that ever does on the title's behalf what the title did not.
//!
//! The swap path splits cleanly in the middle. The title reserves sixty-four
//! ring dwords, calls `VdSwap`, and the kernel fills those dwords with a
//! texture fetch constant followed by an `XE_SWAP` packet; the title then
//! advances the write pointer, and the emulator's command processor — its own
//! code, at its own pace — decodes the packet and presents. A title that never
//! reaches `VdSwap` leaves the whole downstream pipeline — the emulator's
//! authentic decode, issue, refresh and present code — with no input.
//!
//! That is the exact shape this module exists for. The packet is data in
//! memory the harness already owns, and everything downstream of the write is
//! the emulator's own code. `lib/gpu/pm4.zig` owns the packet *arithmetic* —
//! header packing, the fetch constant, the `'SWAP'` signature, the no-op fill —
//! and this owns `guest memory`, the part the arithmetic cannot be tested
//! without. It writes a ready packet into the published ring with the same
//! byte order and wraparound the guest's own stores use, and it says exactly
//! what it wrote.
//!
//! ## Why it is a queue and not a hack
//!
//! A queue has an owner and a ledger. The owner is Rosette, which is why every
//! counter here is provenance — a packet this module wrote must never be
//! mistaken for one the title wrote, and the ring wire format is the only
//! thing the two share. The ledger is the record of what was actually written:
//! dwords, pointer movement, wraparound, and every refusal, so a run that
//! injected nothing still says why instead of reading the same as a run that
//! never triggered.
//!
//! ## What it does not do
//!
//! It does not advance the emulator's own write pointer register. The pointer
//! is memory-mapped and its stores are executed by guest code inside the
//! emulator, so the value this module computes is the value the guest would
//! have published — recorded and reported, and left for the emulator's
//! ring-change watch to act on. Supplying the packet and naming the missing
//! pointer is the honest boundary of what a memory write can reach; pretending
//! the pointer moved would be a lie a counter could not take back.

const std = @import("std");
const pm4 = @import("pm4.zig");

/// The span `VdSwap` is given to work with, mirrored from `pm4` so a caller of
/// the injection API never has to know where the reservation lives.
pub const swap_reservation_dwords: u32 = pm4.swap_reservation_dwords;

/// What one injection did, in ring terms.
pub const Inject = struct {
    dwords_written: u32 = 0,
    write_pointer_before: u32 = 0,
    write_pointer_after: u32 = 0,
    /// The write crossed the ring's end and continued at its base.
    wrapped: bool = false,
};

/// Why an injection could not be performed. Each value names a distinct
/// missing precondition, because "refused" says nothing a reader can act on.
pub const Blocked = enum {
    /// Ring geometry has not been observed, so there is nowhere to write.
    no_geometry,
    /// No write pointer is known, so the packet has no position in the ring.
    no_write_pointer,
    /// The ring is smaller than the packet that must fit in it.
    ring_too_small,
    /// The write pointer is outside the ring it points into.
    write_pointer_out_of_range,
    /// None of the ring's host projections are writable from here.
    not_writable,
    /// The front buffer the swap names is not one a display could produce.
    frontbuffer_implausible,

    pub fn label(self: Blocked) []const u8 {
        return switch (self) {
            .no_geometry => "ring geometry has not been observed, so there is nowhere to write",
            .no_write_pointer => "no write pointer is known, so the packet has no position in the ring",
            .ring_too_small => "the ring is smaller than the swap reservation that must fit in it",
            .write_pointer_out_of_range => "the write pointer lies outside the ring it points into",
            .not_writable => "none of the ring's host projections are writable from here; the emulator's memory view base has not been discovered",
            .frontbuffer_implausible => "the front buffer the swap names is not one a display could plausibly have produced; writing it would make the command processor assert",
        };
    }
};

/// Write dwords into the ring with the guest's own byte order and wraparound.
///
/// The ring is bytes on the wire but dwords in the guest's address space, and
/// the guest is PowerPC, so every dword is stored big-endian — the same
/// conversion the emulator's own producer applies. The write pointer is a
/// dword index; a packet that runs past the ring's end continues at its base,
/// exactly as a real submission would.
pub fn injectSequence(
    ring: []u8,
    ring_dwords: u32,
    write_pointer: u32,
    dwords: []const u32,
) ?Inject {
    const ring_bytes: usize = @as(usize, ring_dwords) * 4;
    if (ring_dwords == 0 or ring.len < ring_bytes) return null;
    if (dwords.len == 0 or dwords.len > ring_dwords) return null;
    if (write_pointer >= ring_dwords) return null;

    const end = @as(u32, @intCast(dwords.len));
    const wrapped = write_pointer + end > ring_dwords;
    for (dwords, 0..) |dword, index| {
        const at = (write_pointer + @as(u32, @intCast(index))) % ring_dwords;
        const byte_at: usize = @as(usize, at) * 4;
        var wire: [4]u8 = undefined;
        std.mem.writeInt(u32, &wire, dword, .big);
        @memcpy(ring[byte_at .. byte_at + 4], &wire);
    }
    return .{
        .dwords_written = end,
        .write_pointer_before = write_pointer,
        .write_pointer_after = (write_pointer + end) % ring_dwords,
        .wrapped = wrapped,
    };
}

/// Build the swap sequence `VdSwap` would have written and inject it.
///
/// One call for the common case: the front buffer is known (a plausible gate
/// the caller already ran), the fetch constant defaults are coherent, and the
/// packet is the reserved sixty-four dwords. Returns the injection, or the
/// blocked reason via the caller's ledger — the build itself cannot fail here
/// because the reservation is fixed and the buffer is stack-sized.
pub fn injectSwap(
    ring: []u8,
    ring_dwords: u32,
    fetch: pm4.FetchConstant,
    swap: pm4.SwapDescription,
    write_pointer: u32,
) ?Inject {
    if (!swap.plausible()) return null;
    var packet: [swap_reservation_dwords]u32 = undefined;
    const used = pm4.encodeSwapSequence(&packet, fetch, swap, swap_reservation_dwords) orelse return null;
    return injectSequence(ring, ring_dwords, write_pointer, packet[0..used]);
}

/// Execution truth for the run: what the synthetic queue actually wrote, kept
/// apart from what the title wrote and from what the substitution layer
/// *decided* to do. The decision ledger answers "what was authorised"; this
/// answers "what landed in memory", and the two must be allowed to disagree —
/// an injection that was blocked is exactly such a disagreement, and hiding it
/// would make a silent refusal read as progress.
pub const Ledger = struct {
    /// Times a packet was written into the ring.
    injections: u64 = 0,
    /// Dwords written in total, all injections.
    dwords_written: u64 = 0,
    /// Times an injection advanced the write pointer.
    pointers_advanced: u64 = 0,
    /// Times an injection was refused, with the most recent reason.
    blocked: u64 = 0,
    last_blocked_by: ?Blocked = null,
    first_step: u64 = 0,
    last_step: u64 = 0,
    last_inject: ?Inject = null,
    /// Whether the write pointer is delivered to the emulator's ring memory
    /// rather than only computed. False until a projection is writable.
    channel_open: bool = false,

    pub fn record(self: *Ledger, inject: Inject, step: u64) void {
        self.injections +|= 1;
        self.dwords_written +|= inject.dwords_written;
        self.pointers_advanced +|= 1;
        if (self.first_step == 0) self.first_step = step;
        self.last_step = step;
        self.last_inject = inject;
    }

    pub fn recordBlocked(self: *Ledger, reason: Blocked) void {
        self.blocked +|= 1;
        self.last_blocked_by = reason;
    }

    /// Whether the queue ever acted on the title's behalf. The single question
    /// a reader of any downstream counter must be able to ask.
    pub fn fabricatedAnything(self: *const Ledger) bool {
        return self.injections != 0;
    }

    pub fn verdict(self: *const Ledger) []const u8 {
        if (self.injections == 0 and self.blocked == 0)
            return "the synthetic queue has never been given anything to inject";
        if (self.injections == 0)
            return "every injection was refused; the blocking reason names the missing capability, and a queue that cannot write is a decision record rather than progress";
        return "the synthetic queue wrote packets into ring memory the title published. Those dwords are Rosette's, not the title's, and nothing downstream may count them as authentic submission until the emulator's own write pointer moves";
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const testing = std.testing;

fn dwordsOf(ring: []const u8, index: u32) u32 {
    var wire: [4]u8 = undefined;
    @memcpy(&wire, ring[@as(usize, index) * 4 ..][0..4]);
    return std.mem.readInt(u32, &wire, .big);
}

test "an injection writes dwords big-endian, the ring's wire format" {
    var ring: [64]u8 = [_]u8{0} ** 64;
    const inject = injectSequence(&ring, 16, 0, &.{ 0x11223344, 0xAABBCCDD }).?;
    try testing.expectEqual(@as(u32, 2), inject.dwords_written);
    try testing.expectEqual(@as(u32, 0), inject.write_pointer_before);
    try testing.expectEqual(@as(u32, 2), inject.write_pointer_after);
    try testing.expect(!inject.wrapped);
    // Big-endian on the wire: the first stored byte is the most significant.
    try testing.expectEqual(@as(u8, 0x11), ring[0]);
    try testing.expectEqual(@as(u8, 0x44), ring[3]);
    try testing.expectEqual(@as(u32, 0x11223344), dwordsOf(&ring, 0));
    try testing.expectEqual(@as(u32, 0xAABBCCDD), dwordsOf(&ring, 1));
}

test "an injection wraps at the ring's end exactly as a real submission does" {
    var ring: [64]u8 = [_]u8{0} ** 64;
    // Ring of 16 dwords, write pointer at 14: a 4-dword write crosses the end.
    const inject = injectSequence(&ring, 16, 14, &.{ 1, 2, 3, 4 }).?;
    try testing.expect(inject.wrapped);
    try testing.expectEqual(@as(u32, 2), inject.write_pointer_after);
    try testing.expectEqual(@as(u32, 1), dwordsOf(&ring, 14));
    try testing.expectEqual(@as(u32, 2), dwordsOf(&ring, 15));
    try testing.expectEqual(@as(u32, 3), dwordsOf(&ring, 0));
    try testing.expectEqual(@as(u32, 4), dwordsOf(&ring, 1));
}

test "an injection that fits exactly does not claim to have wrapped" {
    var ring: [64]u8 = [_]u8{0} ** 64;
    const inject = injectSequence(&ring, 16, 12, &.{ 1, 2, 3, 4 }).?;
    try testing.expect(!inject.wrapped);
    try testing.expectEqual(@as(u32, 0), inject.write_pointer_after);
}

test "every missing precondition is refused with a different name" {
    var ring: [64]u8 = [_]u8{0} ** 64;
    // Ring too small for the dwords.
    try testing.expect(injectSequence(ring[0..8], 16, 0, &.{ 1, 2, 3 }) == null);
    // No room for a single dword.
    try testing.expect(injectSequence(&ring, 0, 0, &.{1}) == null);
    // No dwords to write.
    try testing.expect(injectSequence(&ring, 16, 0, &.{}) == null);
    // A write pointer outside the ring.
    try testing.expect(injectSequence(&ring, 16, 16, &.{1}) == null);
    // More dwords than the ring holds.
    try testing.expect(injectSequence(&ring, 4, 0, &.{ 1, 2, 3, 4, 5 }) == null);
}

// The strongest proof the packet is right: write it, read it back with the
// ring's byte order, and let the emulator's own decoder recognise it.
test "an injected swap packet round-trips through the emulator's swap decoder" {
    var ring: [256]u8 = [_]u8{0} ** 256;
    var fetch = pm4.FetchConstant{};
    fetch.setBaseAddress(0x1E_0000);
    fetch.setSize2d(1280, 720);
    fetch.setTiled(true);
    const swap = pm4.SwapDescription{
        .frontbuffer_physical_address = 0x1E_0000,
        .width = 1280,
        .height = 720,
    };

    // The reservation is fixed at 64 dwords and the tail is no-op filled,
    // exactly like VdSwap's own write — 12 dwords of packet, 52 of filler.
    const inject = injectSwap(&ring, 64, fetch, swap, 0).?;
    try testing.expectEqual(@as(u32, 64), inject.dwords_written);
    try testing.expectEqual(@as(u32, 0), inject.write_pointer_after);

    var dwords: [64]u32 = undefined;
    for (0..64) |index| dwords[index] = dwordsOf(&ring, @intCast(index));
    const decoded = pm4.decodeSwapSequence(&dwords).?;
    try testing.expectEqual(@as(u32, 0x1E_0000), decoded.frontbuffer_physical_address);
    try testing.expectEqual(@as(u32, 1280), decoded.width);
    try testing.expectEqual(@as(u32, 720), decoded.height);
}

test "an implausible front buffer refuses the injection" {
    var ring: [256]u8 = [_]u8{0} ** 256;
    const swap = pm4.SwapDescription{ .frontbuffer_physical_address = 0, .width = 5, .height = 5 };
    try testing.expect(injectSwap(&ring, 64, pm4.FetchConstant{}, swap, 0) == null);
}

test "the ledger counts injections separately from refusals" {
    var ledger = Ledger{};
    var ring: [64]u8 = [_]u8{0} ** 64;
    const inject = injectSequence(&ring, 16, 0, &.{ 0x53574150, 7 }).?;
    ledger.record(inject, 100);
    ledger.record(inject, 200);
    ledger.recordBlocked(.not_writable);
    try testing.expectEqual(@as(u64, 2), ledger.injections);
    try testing.expectEqual(@as(u64, 4), ledger.dwords_written);
    try testing.expectEqual(@as(u64, 2), ledger.pointers_advanced);
    try testing.expectEqual(@as(u64, 1), ledger.blocked);
    try testing.expectEqual(Blocked.not_writable, ledger.last_blocked_by.?);
    try testing.expect(ledger.fabricatedAnything());
    try testing.expectEqual(@as(u64, 100), ledger.first_step);
    try testing.expectEqual(@as(u64, 200), ledger.last_step);
    try testing.expect(std.mem.indexOf(u8, ledger.verdict(), "Rosette's, not the title's") != null);
}

test "a ledger that never acted says so rather than reading as clean" {
    const ledger = Ledger{};
    try testing.expect(!ledger.fabricatedAnything());
    try testing.expect(std.mem.indexOf(u8, ledger.verdict(), "never been given anything") != null);

    var refused = Ledger{};
    refused.recordBlocked(.no_write_pointer);
    try testing.expect(std.mem.indexOf(u8, refused.verdict(), "blocking reason names the missing capability") != null);
}

test "every blocked reason explains itself" {
    inline for (.{
        Blocked.no_geometry,               Blocked.no_write_pointer,
        Blocked.ring_too_small,            Blocked.write_pointer_out_of_range,
        Blocked.not_writable,              Blocked.frontbuffer_implausible,
    }) |reason| {
        try testing.expect(reason.label().len > 40);
    }
}