//! Route-independent: Xenia's log ring geometry and the disruptor sequence
//! protocol it publishes with.
//!
//! Xenia's logger is a multi-producer, single-consumer disruptor over an 8 MiB
//! buffer of 256-byte blocks. Producers claim a range of sequence numbers,
//! write into the blocks those numbers index, and publish; the consumer waits
//! until a range is published and then drains it.
//!
//! ## Why a log ring is worth a contract
//!
//! Because it is the single most misread thing in a Rosette trace. The hot
//! sites in the current run are `disruptorplus::spin_wait::yield_processor`,
//! `disruptorplus::difference` and `spin_wait::spin_once`, and the obvious
//! reading of "ring buffer spin" in a GPU-stalled emulator is that the *command*
//! ring is spinning. It is not: `disruptorplus` appears in exactly two places
//! in Xenia — `base/logging.cc` and `base/threading_timer_queue.cc` — and the
//! GPU ring is `xe::RingBuffer`, an entirely different type.
//!
//! So a trace that looks like a graphics stall is often a log consumer waiting
//! for a producer that has nothing to say. Writing the distinction down is the
//! point of this package.
//!
//! ## Sequences are unsigned and wrap, so ordering is by difference
//!
//! A disruptor sequence counts monotonically and is allowed to wrap. Comparing
//! two of them with `<` is wrong: after a wrap the comparison inverts and the
//! consumer concludes the producer has gone backwards, which manifests as the
//! log stopping and never resuming. The correct test is the *signed difference*
//! of the unsigned values, which stays correct across one wrap.
//!
//! ## What this package is not
//!
//! * It is not a ring. It holds no buffer, no sequence and no claim state.
//! * It does not log. Emitting a line is an effect.
//! * It does not describe the GPU ring. That is
//!   `pkg/common/xenia/vd-ring-contract`, and conflating the two is exactly the
//!   mistake this package exists to prevent.

const std = @import("std");

/// The log buffer. 8 MiB of 256-byte blocks.
pub const buffer_bytes: usize = 8 * 1024 * 1024;
pub const block_bytes: usize = 256;
pub const block_count: usize = buffer_bytes / block_bytes;
/// Block count is a power of two, so the index is a mask rather than a modulo.
pub const block_index_mask: usize = block_count - 1;

/// Sequence numbers are unsigned 64-bit and wrap.
pub const Sequence = u64;

/// The byte offset a sequence indexes.
pub fn blockOffset(sequence: Sequence) usize {
    return (@as(usize, @truncate(sequence)) & block_index_mask) * block_bytes;
}

/// Blocks a payload of this size occupies, rounding up.
pub fn blocksFor(byte_size: usize) usize {
    return (byte_size + (block_bytes - 1)) / block_bytes;
}

/// The signed distance from `a` to `b`.
///
/// The only correct way to order two disruptor sequences. A plain `<`
/// comparison inverts after a wrap, and the consumer then concludes the
/// producer moved backwards — which stops the log permanently, long after the
/// run started, with nothing reporting an error.
pub fn difference(a: Sequence, b: Sequence) i64 {
    return @bitCast(a -% b);
}

/// Whether `published` has reached or passed `wanted`.
pub fn hasReached(published: Sequence, wanted: Sequence) bool {
    return difference(published, wanted) >= 0;
}

/// Whether a claimed range fits without overwriting unconsumed blocks.
///
/// A producer may claim up to `block_count` ahead of the consumer. Claiming
/// further overwrites a block the consumer has not read, and the line that was
/// there is lost silently — which looks like a missing log line rather than a
/// full ring.
pub fn claimFits(claim_end: Sequence, consumed: Sequence) bool {
    return difference(claim_end, consumed) <= @as(i64, @intCast(block_count));
}

/// What a spinning disruptor site actually indicates.
///
/// Stated as data so a reader does not have to re-derive it from the symbol
/// name at the moment they are looking at a stalled GPU.
pub const SpinSubsystem = enum {
    logging,
    timer_queue,

    pub fn sourceFile(self: SpinSubsystem) []const u8 {
        return switch (self) {
            .logging => "src/xenia/base/logging.cc",
            .timer_queue => "src/xenia/base/threading_timer_queue.cc",
        };
    }

    /// Whether a spin here means the GPU command ring is stalled.
    ///
    /// Always false. The GPU ring is `xe::RingBuffer` and does not use
    /// disruptor sequences at all.
    pub fn impliesGraphicsStall(self: SpinSubsystem) bool {
        _ = self;
        return false;
    }
};

/// The disruptor symbols that appear in a Rosette trace, and what they mean.
pub const spin_symbols = [_][]const u8{
    "disruptorplus::spin_wait::yield_processor",
    "disruptorplus::spin_wait::spin_once",
    "disruptorplus::difference",
    "disruptorplus::sequence_barrier",
};

/// Whether a symbol name belongs to the disruptor, and therefore to the log or
/// timer subsystem rather than to the GPU.
pub fn isDisruptorSymbol(symbol: []const u8) bool {
    return std.mem.indexOf(u8, symbol, "disruptorplus") != null;
}

pub fn contractIsWellFormed() bool {
    if (!std.math.isPowerOfTwo(block_count)) return false;
    if (block_count * block_bytes != buffer_bytes) return false;
    if (difference(0, 1) != -1) return false;
    return true;
}

test "the contract is internally consistent" {
    try std.testing.expect(contractIsWellFormed());
}

test "the ring is 8 MiB of 256 byte blocks" {
    try std.testing.expectEqual(@as(usize, 8 * 1024 * 1024), buffer_bytes);
    try std.testing.expectEqual(@as(usize, 256), block_bytes);
    try std.testing.expectEqual(@as(usize, 32768), block_count);
    // A power of two, which is why the index is a mask.
    try std.testing.expect(std.math.isPowerOfTwo(block_count));
    try std.testing.expectEqual(@as(usize, 32767), block_index_mask);
}

test "sequence ordering survives a wrap" {
    // The failure this prevents: after a wrap a plain `<` inverts, the
    // consumer concludes the producer went backwards, and the log stops
    // permanently — minutes into a run, with nothing reporting an error.
    const before: Sequence = std.math.maxInt(u64) - 1;
    const after: Sequence = 1; // wrapped past the end

    // The naive comparison says the producer moved backwards.
    try std.testing.expect(after < before);
    // The difference says it advanced by three, which is the truth.
    try std.testing.expectEqual(@as(i64, 3), difference(after, before));
    try std.testing.expect(hasReached(after, before));
}

test "difference is signed and symmetric" {
    try std.testing.expectEqual(@as(i64, 0), difference(100, 100));
    try std.testing.expectEqual(@as(i64, 5), difference(105, 100));
    try std.testing.expectEqual(@as(i64, -5), difference(100, 105));
}

test "hasReached is inclusive of the wanted sequence" {
    // Off by one here makes the consumer wait for a block the producer has
    // already published, which stalls exactly one line short forever.
    try std.testing.expect(hasReached(100, 100));
    try std.testing.expect(hasReached(101, 100));
    try std.testing.expect(!hasReached(99, 100));
}

test "block offsets wrap by mask, not by modulo" {
    try std.testing.expectEqual(@as(usize, 0), blockOffset(0));
    try std.testing.expectEqual(@as(usize, 256), blockOffset(1));
    // The last block, then back to the first.
    try std.testing.expectEqual(buffer_bytes - block_bytes, blockOffset(block_count - 1));
    try std.testing.expectEqual(@as(usize, 0), blockOffset(block_count));
    try std.testing.expectEqual(@as(usize, 256), blockOffset(block_count + 1));
}

test "a payload occupies whole blocks" {
    try std.testing.expectEqual(@as(usize, 0), blocksFor(0));
    try std.testing.expectEqual(@as(usize, 1), blocksFor(1));
    try std.testing.expectEqual(@as(usize, 1), blocksFor(256));
    try std.testing.expectEqual(@as(usize, 2), blocksFor(257));
    // A long diagnostic line spans several.
    try std.testing.expectEqual(@as(usize, 4), blocksFor(1000));
}

test "a claim may not lap the consumer" {
    // Claiming past the ring overwrites a block the consumer has not read,
    // and the line in it is lost silently — which reads as a missing log line
    // rather than a full ring.
    try std.testing.expect(claimFits(block_count, 0));
    try std.testing.expect(!claimFits(block_count + 1, 0));
    // With the consumer ahead, the same claim fits again.
    try std.testing.expect(claimFits(block_count + 1, 1));
}

test "a spinning disruptor site is never a graphics stall" {
    // The misreading this package exists for. The GPU ring is xe::RingBuffer
    // and uses no disruptor sequences; disruptorplus appears in exactly two
    // files, neither of them graphics.
    try std.testing.expect(!SpinSubsystem.logging.impliesGraphicsStall());
    try std.testing.expect(!SpinSubsystem.timer_queue.impliesGraphicsStall());
    try std.testing.expectEqualStrings(
        "src/xenia/base/logging.cc",
        SpinSubsystem.logging.sourceFile(),
    );
    try std.testing.expectEqualStrings(
        "src/xenia/base/threading_timer_queue.cc",
        SpinSubsystem.timer_queue.sourceFile(),
    );
}

test "disruptor symbols are recognisable from a trace" {
    // These are the exact names that appear as hot sites in a Rosette run.
    for (spin_symbols) |symbol| {
        try std.testing.expect(isDisruptorSymbol(symbol));
    }
    // A mangled name from a real trace still matches.
    try std.testing.expect(isDisruptorSymbol("__ZN13disruptorplus9spin_wait15yield_processorEv"));
    try std.testing.expect(isDisruptorSymbol("__ZN13disruptorplus10differenceEyy"));
    // The GPU ring's own symbols do not.
    try std.testing.expect(!isDisruptorSymbol("__ZN2xe10RingBuffer4ReadEv"));
    try std.testing.expect(!isDisruptorSymbol("CommandProcessor::ExecutePacket"));
}
