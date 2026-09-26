//! Guard bytes after every guest heap block, checked when the block is
//! freed and, for blocks still live, when the run ends.
//!
//! Both 2026-09-24/25 Halo 3 failures were memory corruption that surfaced
//! far from where it happened: a text file full of NULs, a file name made of
//! a pointer's bytes, an allocation of 10.8 GB three frames from the store
//! that was lost. A write past the end of a heap block is the commonest way
//! a guest - or an emulator executing it wrongly - corrupts its neighbour,
//! and the neighbour is where it is noticed, long afterwards. A guard names
//! the block that was overrun, who allocated it, and the first guard byte
//! that changed, at the first free that can see it.
//!
//! The guard sits in the block's own backing, past its logical length:
//! `guestAlloc` reserves `size + guard_bytes`, reuse only ever hands a block
//! back at its exact logical size, and an in-place shrink re-arms the guard
//! at the new end. The guest never sees it: every size query answers the
//! logical length. Each allocation record keeps the guard length it was
//! given, so a block allocated unguarded is never checked against bytes
//! that belong to its neighbour.

const std = @import("std");

/// Bytes of guard after each block. Sixteen keeps the next block's 16-byte
/// alignment whenever the block's size is itself a multiple of 16.
pub const default_guard_bytes: u64 = 16;
/// Not zero, which is what an unwritten byte of fresh memory reads as, and
/// not 0xFF, which is the commonest all-ones store.
pub const pattern: u8 = 0xFD;
/// Alignment from which a block goes unguarded. Page-aligned requests are
/// thread stacks and VirtualAlloc-style regions sized in whole pages; a
/// guard after one would start the next page-aligned block a whole page
/// later, doubling what a run of single-page blocks costs.
pub const unguarded_alignment: u64 = 0x1000;

/// The guard a block of `alignment` gets when `configured` bytes are asked
/// for (zero turns guards off).
pub fn guardBytesFor(configured: u64, alignment: u64) u64 {
    return if (alignment >= unguarded_alignment) 0 else configured;
}

pub fn arm(guard: []u8) void {
    @memset(guard, pattern);
}

pub const Damage = struct {
    /// Offset of the first changed byte from the block's logical end.
    first_offset: usize,
    first_value: u8,
    changed: usize,
};

/// Null when every guard byte still holds the pattern.
pub fn check(guard: []const u8) ?Damage {
    var damage: ?Damage = null;
    for (guard, 0..) |byte, offset| {
        if (byte == pattern) continue;
        if (damage) |*found| {
            found.changed += 1;
        } else {
            damage = .{ .first_offset = offset, .first_value = byte, .changed = 1 };
        }
    }
    return damage;
}

test "an untouched guard passes and an overrun is located" {
    var block = [_]u8{0} ** 48;
    const guard = block[32..48];
    arm(guard);
    try std.testing.expect(check(guard) == null);
    block[32] = 0x41;
    block[35] = 0x00;
    const damage = check(guard).?;
    try std.testing.expectEqual(@as(usize, 0), damage.first_offset);
    try std.testing.expectEqual(@as(u8, 0x41), damage.first_value);
    try std.testing.expectEqual(@as(usize, 2), damage.changed);
}

test "an empty guard never reports" {
    try std.testing.expect(check(&.{}) == null);
}

test "page-aligned blocks go unguarded and a zero configuration turns guards off" {
    try std.testing.expectEqual(default_guard_bytes, guardBytesFor(default_guard_bytes, 16));
    try std.testing.expectEqual(default_guard_bytes, guardBytesFor(default_guard_bytes, 0x800));
    try std.testing.expectEqual(@as(u64, 0), guardBytesFor(default_guard_bytes, 0x1000));
    try std.testing.expectEqual(@as(u64, 0), guardBytesFor(default_guard_bytes, 0x10000));
    try std.testing.expectEqual(@as(u64, 0), guardBytesFor(0, 16));
}
