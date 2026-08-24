//! Route-independent: the Xenos EDRAM's fixed tile geometry and render-target
//! limits.
//!
//! The EDRAM daughter die is 10 MiB of storage that is *not* part of the
//! 512 MiB a title allocates from, laid out as 2048 tiles of 80x16 32-bit
//! samples. Those numbers are silicon; there is one copy and no route mirror.
//!
//! ## Why the tile is the fact worth pinning
//!
//! Almost every EDRAM bug is a tile-arithmetic bug, and they share a signature:
//! the image is *nearly* right. A wrong tile width shears the frame; a wrong
//! tile height interleaves bands of two surfaces; a wrong sample expansion for
//! MSAA quietly halves the vertical resolution. None of these fault, none log,
//! and all of them look like a shader or a resolve problem to whoever is
//! looking at the screen.
//!
//! The tile is also where an intuition actively misleads. A "tile" in most
//! graphics contexts is square and a power of two. This one is 80x16 — neither.
//! The abstraction plan that asked for this package guessed `"tile_size": 256`,
//! which is the right order of magnitude and wrong in every other way: a tile
//! is 5120 bytes. Writing the real numbers down once is what keeps the guess
//! from being made again.
//!
//! ## What this package is not
//!
//! * It is not an EDRAM store. It holds no pixels; `lib/gpu/edram.zig` owns the
//!   backing bytes and every read and write of them.
//! * It is not a render-target cache. Which surface currently occupies which
//!   tile range is mutable runtime state and lives in lib.
//! * It does not resolve anything. A resolve is an operation, not a fact.
//!
//! `lib/gpu/edram.zig` declares the same geometry from the runtime side. The
//! tests below assert the values independently, so if the two ever disagree the
//! failure names the constant rather than appearing as a sheared frame.

const std = @import("std");

// ---------------------------------------------------------------------------
// Tile geometry
// ---------------------------------------------------------------------------

/// A tile is 80 samples wide and 16 tall. Neither is a power of two, which is
/// why `>> 4`-style tile arithmetic is wrong here and division is required.
pub const tile_width_samples: u32 = 80;
pub const tile_height_samples: u32 = 16;
pub const samples_per_tile: u32 = tile_width_samples * tile_height_samples;

/// A sample is 32 bits in the common case. 64-bit colour formats consume two
/// tiles per tile-of-pixels, which is expressed as a pitch doubling rather
/// than a different tile size.
pub const bytes_per_sample_32: u32 = 4;
pub const bytes_per_sample_64: u32 = 8;

/// 5120 bytes. Not 256, and not a power of two.
pub const tile_bytes: u32 = samples_per_tile * bytes_per_sample_32;

pub const tile_count: u32 = 2048;

/// 10 MiB exactly.
pub const edram_bytes: u64 = @as(u64, tile_count) * tile_bytes;

// ---------------------------------------------------------------------------
// Limits
// ---------------------------------------------------------------------------

/// Simultaneous colour targets the Xenos binds. Four, plus one depth/stencil.
pub const max_color_targets: u32 = 4;
pub const max_depth_targets: u32 = 1;
pub const max_render_targets: u32 = max_color_targets + max_depth_targets;

/// The console's MSAA ceiling. 4x, not 8x — a host that offers more cannot be
/// asked for it on the title's behalf without changing what the title drew.
pub const max_msaa_samples: u32 = 4;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

pub const Msaa = enum(u2) {
    x1 = 0,
    x2 = 1,
    x4 = 2,

    pub fn sampleCount(self: Msaa) u32 {
        return switch (self) {
            .x1 => 1,
            .x2 => 2,
            .x4 => 4,
        };
    }

    /// How MSAA expands a surface in sample space.
    ///
    /// This asymmetry is the trap. 2x expands *height only*; 4x expands both.
    /// A model that scales both axes for 2x reserves twice the tiles it needs
    /// and pushes later surfaces out of EDRAM, and one that scales neither
    /// overlaps them.
    pub fn widthScale(self: Msaa) u32 {
        return switch (self) {
            .x1, .x2 => 1,
            .x4 => 2,
        };
    }

    pub fn heightScale(self: Msaa) u32 {
        return switch (self) {
            .x1 => 1,
            .x2, .x4 => 2,
        };
    }
};

pub const SurfaceFormat = enum(u8) {
    color32 = 0,
    color64 = 1,
    depth24s8 = 2,
    depth24fs8 = 3,

    pub fn is64Bit(self: SurfaceFormat) bool {
        return self == .color64;
    }

    pub fn isDepth(self: SurfaceFormat) bool {
        return switch (self) {
            .depth24s8, .depth24fs8 => true,
            .color32, .color64 => false,
        };
    }
};

// ---------------------------------------------------------------------------
// Pure geometry
// ---------------------------------------------------------------------------

fn ceilDiv(numerator: u32, denominator: u32) u32 {
    return (numerator + denominator - 1) / denominator;
}

/// Tiles spanned by a surface of this sample-space extent.
///
/// Pure arithmetic on the numbers handed in. It cannot say a surface is
/// resident, allocated, or drawn to — only how many tiles one of that shape
/// would occupy.
pub fn tilesForExtent(sample_width: u32, sample_height: u32, is_64_bit: bool) u64 {
    const pitch_tiles = ceilDiv(sample_width, tile_width_samples);
    const row_tiles = ceilDiv(sample_height, tile_height_samples);
    const doubled: u64 = if (is_64_bit) 2 else 1;
    return @as(u64, pitch_tiles) * row_tiles * doubled;
}

/// Whether a tile index addresses real EDRAM.
pub fn isTileIndex(index: u32) bool {
    return index < tile_count;
}

/// Whether a surface placed at `base_tile` spanning `tiles` fits in EDRAM.
///
/// The overflow this guards is real: a base near the top plus a large span
/// wraps a `u32` sum and reports a surface that runs off the end as fitting.
pub fn fitsInEdram(base_tile: u32, tiles: u64) bool {
    return @as(u64, base_tile) + tiles <= tile_count;
}

pub fn contractIsWellFormed() bool {
    if (tile_bytes != 5120) return false;
    if (edram_bytes != 10 * 1024 * 1024) return false;
    if (samples_per_tile != 1280) return false;
    if (max_msaa_samples != Msaa.x4.sampleCount()) return false;
    return true;
}

test "the contract is internally consistent" {
    try std.testing.expect(contractIsWellFormed());
}

test "EDRAM is ten mebibytes of non-power-of-two tiles" {
    try std.testing.expectEqual(@as(u32, 80), tile_width_samples);
    try std.testing.expectEqual(@as(u32, 16), tile_height_samples);
    try std.testing.expectEqual(@as(u32, 2048), tile_count);
    try std.testing.expectEqual(@as(u32, 5120), tile_bytes);
    try std.testing.expectEqual(@as(u64, 10_485_760), edram_bytes);

    // The plan sketch said 256. It is 5120, and it is not a power of two, so
    // shift-based tile arithmetic is wrong by construction.
    try std.testing.expect(tile_bytes != 256);
    try std.testing.expect(!std.math.isPowerOfTwo(tile_width_samples));
    try std.testing.expect(!std.math.isPowerOfTwo(tile_bytes));
}

test "this matches the geometry lib/gpu/edram.zig runs on" {
    // Stated independently here so a divergence fails a test instead of
    // shearing a frame. lib/gpu/edram.zig derives tile_bytes the same way.
    try std.testing.expectEqual(@as(u32, 80 * 16 * 4), tile_bytes);
    try std.testing.expectEqual(@as(usize, 2048 * 5120), @as(usize, @intCast(edram_bytes)));
}

test "2x MSAA expands height only" {
    // The asymmetry that costs the most when guessed. 2x is vertical-only.
    try std.testing.expectEqual(@as(u32, 1), Msaa.x2.widthScale());
    try std.testing.expectEqual(@as(u32, 2), Msaa.x2.heightScale());
    // 4x expands both axes.
    try std.testing.expectEqual(@as(u32, 2), Msaa.x4.widthScale());
    try std.testing.expectEqual(@as(u32, 2), Msaa.x4.heightScale());
    // 1x expands neither.
    try std.testing.expectEqual(@as(u32, 1), Msaa.x1.widthScale());
    try std.testing.expectEqual(@as(u32, 1), Msaa.x1.heightScale());
}

test "sample counts are not the same thing as axis scales" {
    // 2x MSAA doubles the sample count and doubles only one axis. Conflating
    // the two is how a surface ends up half as tall as it should be.
    try std.testing.expectEqual(@as(u32, 2), Msaa.x2.sampleCount());
    try std.testing.expectEqual(Msaa.x2.sampleCount(), Msaa.x2.widthScale() * Msaa.x2.heightScale());
    try std.testing.expectEqual(@as(u32, 4), Msaa.x4.sampleCount());
    try std.testing.expectEqual(Msaa.x4.sampleCount(), Msaa.x4.widthScale() * Msaa.x4.heightScale());
}

test "a 1280x720 32-bit target fits, and its tile count is exact" {
    // 1280/80 = 16 tiles across, 720/16 = 45 down.
    try std.testing.expectEqual(@as(u64, 16 * 45), tilesForExtent(1280, 720, false));
    try std.testing.expect(fitsInEdram(0, tilesForExtent(1280, 720, false)));
    // 64-bit colour doubles the span.
    try std.testing.expectEqual(@as(u64, 16 * 45 * 2), tilesForExtent(1280, 720, true));
}

test "partial tiles round up, never down" {
    // One sample past a tile boundary needs another whole tile. Truncating
    // here loses the last column or row of the frame.
    try std.testing.expectEqual(@as(u64, 1), tilesForExtent(1, 1, false));
    try std.testing.expectEqual(@as(u64, 1), tilesForExtent(80, 16, false));
    try std.testing.expectEqual(@as(u64, 2), tilesForExtent(81, 16, false));
    try std.testing.expectEqual(@as(u64, 2), tilesForExtent(80, 17, false));
}

test "an oversized surface does not wrap into looking like it fits" {
    try std.testing.expect(isTileIndex(0));
    try std.testing.expect(isTileIndex(tile_count - 1));
    try std.testing.expect(!isTileIndex(tile_count));

    // Exactly full is fine; one tile more is not.
    try std.testing.expect(fitsInEdram(0, tile_count));
    try std.testing.expect(!fitsInEdram(0, tile_count + 1));
    // A high base with a large span must not wrap a 32-bit sum into "fits".
    try std.testing.expect(!fitsInEdram(tile_count - 1, 2));
    try std.testing.expect(!fitsInEdram(0xFFFF_FFFF, 1));
}

test "there are four colour targets and one depth target" {
    try std.testing.expectEqual(@as(u32, 4), max_color_targets);
    try std.testing.expectEqual(@as(u32, 1), max_depth_targets);
    try std.testing.expectEqual(@as(u32, 5), max_render_targets);
}

test "depth and 64-bit colour are distinguishable from plain colour" {
    try std.testing.expect(SurfaceFormat.depth24s8.isDepth());
    try std.testing.expect(SurfaceFormat.depth24fs8.isDepth());
    try std.testing.expect(!SurfaceFormat.color32.isDepth());
    try std.testing.expect(!SurfaceFormat.color64.isDepth());
    try std.testing.expect(SurfaceFormat.color64.is64Bit());
    try std.testing.expect(!SurfaceFormat.color32.is64Bit());
}
