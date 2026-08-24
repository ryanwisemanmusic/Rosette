//! Tile to texture address mapping.
//!
//! When a render target resolves out to main memory it stops being a tiled
//! EDRAM surface and becomes a texture the title can sample. This file maps
//! between the two address spaces.
//!
//! ## Rounding is where this goes wrong
//!
//! EDRAM works in 80x16-sample tiles; textures work in pixels with their own
//! pitch alignment. Neither dimension divides the other, so a mapping that
//! rounds in the wrong direction — or rounds once instead of twice — produces
//! an image offset by a fraction of a tile. The picture is recognisable, which
//! means the bug survives review by eye.

const std = @import("std");
const contract = @import("xenia_render_target_contract");

pub const Error = error{
    OutOfSurface,
    DegenerateExtent,
};

/// The tile a pixel falls in, and its position inside that tile.
pub const TileLocation = struct {
    tile_x: u32,
    tile_y: u32,
    /// Offset within the tile, in samples.
    inner_x: u32,
    inner_y: u32,

    /// The tile's linear index given a pitch in tiles.
    pub fn tileIndex(self: TileLocation, tile_pitch: u32) u32 {
        return self.tile_y * tile_pitch + self.tile_x;
    }

    /// Byte offset of this sample within EDRAM, given a tile pitch.
    pub fn byteOffset(self: TileLocation, tile_pitch: u32) u64 {
        const tile = @as(u64, self.tileIndex(tile_pitch)) * contract.tile_bytes;
        const inner = (@as(u64, self.inner_y) * contract.tile_width_samples + self.inner_x) *
            contract.bytes_per_sample_32;
        return tile + inner;
    }
};

/// Locate a sample-space coordinate within the tile grid.
pub fn locate(sample_x: u32, sample_y: u32) TileLocation {
    return .{
        .tile_x = sample_x / contract.tile_width_samples,
        .tile_y = sample_y / contract.tile_height_samples,
        .inner_x = sample_x % contract.tile_width_samples,
        .inner_y = sample_y % contract.tile_height_samples,
    };
}

/// Tiles across, for a surface of this sample width.
///
/// Rounds up: a surface one sample wider than a tile boundary needs another
/// whole tile column, and truncating loses the right edge of every frame whose
/// width is not a multiple of 80.
pub fn tilePitchFor(sample_width: u32) u32 {
    return (sample_width + contract.tile_width_samples - 1) / contract.tile_width_samples;
}

pub fn tileRowsFor(sample_height: u32) u32 {
    return (sample_height + contract.tile_height_samples - 1) / contract.tile_height_samples;
}

/// The linear texture offset a resolved pixel lands at.
///
/// The destination is untiled, so this is the straightforward row-major
/// calculation. It is here rather than at the call site so that the tiled and
/// untiled halves of a resolve sit next to each other and cannot be confused.
pub fn linearOffset(x: u32, y: u32, row_pitch_pixels: u32, bytes_per_pixel: u32) u64 {
    return (@as(u64, y) * row_pitch_pixels + x) * bytes_per_pixel;
}

/// Map a whole resolve region, reporting the first coordinate that falls
/// outside the source surface.
pub fn validateRegion(
    sample_width: u32,
    sample_height: u32,
    origin_x: u32,
    origin_y: u32,
    width: u32,
    height: u32,
) Error!void {
    if (width == 0 or height == 0) return error.DegenerateExtent;
    // Checked in u64: a large origin plus a large extent wraps a u32 sum and
    // reports a region that runs off the surface as being inside it.
    if (@as(u64, origin_x) + width > sample_width) return error.OutOfSurface;
    if (@as(u64, origin_y) + height > sample_height) return error.OutOfSurface;
}

test "the origin is the first sample of the first tile" {
    const location = locate(0, 0);
    try std.testing.expectEqual(@as(u32, 0), location.tile_x);
    try std.testing.expectEqual(@as(u32, 0), location.tile_y);
    try std.testing.expectEqual(@as(u32, 0), location.inner_x);
    try std.testing.expectEqual(@as(u64, 0), location.byteOffset(16));
}

test "a tile boundary advances the tile, not the inner offset" {
    // 80 and 16 are the boundaries; neither is a power of two, so this cannot
    // be done with a mask.
    const across = locate(80, 0);
    try std.testing.expectEqual(@as(u32, 1), across.tile_x);
    try std.testing.expectEqual(@as(u32, 0), across.inner_x);

    const down = locate(0, 16);
    try std.testing.expectEqual(@as(u32, 1), down.tile_y);
    try std.testing.expectEqual(@as(u32, 0), down.inner_y);

    // One short of the boundary stays in the first tile at its last sample.
    const edge = locate(79, 15);
    try std.testing.expectEqual(@as(u32, 0), edge.tile_x);
    try std.testing.expectEqual(@as(u32, 0), edge.tile_y);
    try std.testing.expectEqual(@as(u32, 79), edge.inner_x);
    try std.testing.expectEqual(@as(u32, 15), edge.inner_y);
}

test "the second tile starts one tile of bytes in" {
    const location = locate(80, 0);
    try std.testing.expectEqual(@as(u64, contract.tile_bytes), location.byteOffset(16));
    try std.testing.expectEqual(@as(u64, 5120), location.byteOffset(16));
}

test "a second tile row is a whole pitch of tiles in" {
    const location = locate(0, 16);
    // 16 tiles across, so the second tile row starts at tile 16.
    try std.testing.expectEqual(@as(u32, 16), location.tileIndex(16));
    try std.testing.expectEqual(@as(u64, 16 * contract.tile_bytes), location.byteOffset(16));
}

test "inner offsets advance by the sample size" {
    const location = locate(1, 0);
    try std.testing.expectEqual(@as(u64, 4), location.byteOffset(16));
    const row = locate(0, 1);
    try std.testing.expectEqual(@as(u64, 80 * 4), row.byteOffset(16));
}

test "tile pitch rounds up" {
    // Truncating loses the right edge of every frame whose width is not a
    // multiple of 80.
    try std.testing.expectEqual(@as(u32, 16), tilePitchFor(1280));
    try std.testing.expectEqual(@as(u32, 17), tilePitchFor(1281));
    try std.testing.expectEqual(@as(u32, 1), tilePitchFor(1));
    try std.testing.expectEqual(@as(u32, 0), tilePitchFor(0));

    try std.testing.expectEqual(@as(u32, 45), tileRowsFor(720));
    try std.testing.expectEqual(@as(u32, 46), tileRowsFor(721));
}

test "a linear destination offset is row major" {
    try std.testing.expectEqual(@as(u64, 0), linearOffset(0, 0, 1280, 4));
    try std.testing.expectEqual(@as(u64, 4), linearOffset(1, 0, 1280, 4));
    try std.testing.expectEqual(@as(u64, 1280 * 4), linearOffset(0, 1, 1280, 4));
}

test "a region inside the surface validates" {
    try validateRegion(1280, 720, 0, 0, 1280, 720);
    try validateRegion(1280, 720, 640, 360, 640, 360);
}

test "a region running past the surface is refused" {
    try std.testing.expectError(error.OutOfSurface, validateRegion(1280, 720, 0, 0, 1281, 720));
    try std.testing.expectError(error.OutOfSurface, validateRegion(1280, 720, 1, 0, 1280, 720));
    try std.testing.expectError(error.OutOfSurface, validateRegion(1280, 720, 0, 1, 1280, 720));
}

test "an origin near the top does not wrap into looking valid" {
    // The u32 sum that wraps: a huge origin plus a huge extent would report
    // a region far outside the surface as being inside it.
    try std.testing.expectError(
        error.OutOfSurface,
        validateRegion(1280, 720, 0xFFFF_FFFF, 0, 2, 2),
    );
}

test "a degenerate region is refused" {
    try std.testing.expectError(error.DegenerateExtent, validateRegion(1280, 720, 0, 0, 0, 720));
    try std.testing.expectError(error.DegenerateExtent, validateRegion(1280, 720, 0, 0, 1280, 0));
}
