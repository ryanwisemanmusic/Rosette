//! Xenos texture tiling: swizzled to linear.
//!
//! Textures on the console are stored in a swizzled tile order rather than row
//! by row. Converting to a host-linear layout is the single most common source
//! of "the image is there but wrong" bugs in an emulator, because every
//! plausible variation of the address arithmetic still produces a picture.
//!
//! ## Why the bit mixing is transcribed rather than derived
//!
//! The swizzle was reverse-engineered from hardware behaviour; it is not a
//! formula anyone derived from first principles. A rearrangement that looks
//! equivalent — reordering the terms, folding a shift — generally is not, and
//! the result is an image with its blocks permuted in a way that still looks
//! like a texture. `lib/gpu/xenos_texture.zig` already carries the canonical
//! 2D and 3D offset functions; this file adds the surface-level walk over them
//! and the bounds checking a cache needs, and deliberately does not re-derive
//! the mixing.

const std = @import("std");
const contract = @import("xenia_texture_contract");

pub const Error = error{
    DegenerateExtent,
    DestinationTooSmall,
    SourceTooSmall,
    UnsupportedFormat,
};

/// The layout of one mip level.
pub const LevelLayout = struct {
    width_texels: u32,
    height_texels: u32,
    /// Blocks across, before tile alignment.
    width_blocks: u32,
    height_blocks: u32,
    /// Blocks across, after rounding up to the 32-block tile edge.
    pitch_blocks: u32,
    block_bytes: u32,

    pub fn linearBytes(self: LevelLayout) u64 {
        return @as(u64, self.width_blocks) * self.height_blocks * self.block_bytes;
    }

    /// Bytes the tiled form occupies, which is larger whenever the pitch was
    /// rounded up. Sizing a tiled surface with the linear number is how a
    /// texture read runs off its own allocation.
    pub fn tiledBytes(self: LevelLayout) u64 {
        return @as(u64, self.pitch_blocks) * self.height_blocks * self.block_bytes;
    }
};

/// Compute a level's layout.
pub fn layoutFor(format: contract.TextureFormat, width: u32, height: u32) Error!LevelLayout {
    if (width == 0 or height == 0) return error.DegenerateExtent;
    const geometry = contract.blockGeometryOf(format) orelse return error.UnsupportedFormat;
    const across = contract.blocksForExtent(width, geometry.block_width);
    const down = contract.blocksForExtent(height, geometry.block_height);
    return .{
        .width_texels = width,
        .height_texels = height,
        .width_blocks = across,
        .height_blocks = down,
        .pitch_blocks = contract.alignPitch(across),
        .block_bytes = geometry.block_bytes,
    };
}

/// Mip dimensions, halving and never reaching zero.
///
/// A mip chain bottoms out at 1x1, not at 0x0. A level that computes to zero
/// makes every size calculation below it zero too, and the tail of the chain
/// silently disappears.
pub fn mipExtent(base: u32, level: u32) u32 {
    if (level >= 32) return 1;
    const shifted = base >> @intCast(level);
    return @max(shifted, 1);
}

/// Levels in a full mip chain for an extent.
pub fn mipLevelCount(width: u32, height: u32) u32 {
    var largest = @max(width, height);
    var levels: u32 = 1;
    while (largest > 1) {
        largest >>= 1;
        levels += 1;
    }
    return levels;
}

/// Copy a tiled surface into a linear one, using a caller-provided offset
/// function.
///
/// The offset function is a parameter rather than a hard-coded call so that
/// the canonical implementation in `lib/gpu/xenos_texture.zig` stays the single
/// source of the bit mixing, and this walk can be tested independently of it.
pub fn untile(
    layout: LevelLayout,
    source: []const u8,
    destination: []u8,
    offsetFn: *const fn (x: u32, y: u32, pitch: u32, block_bytes: u32) u64,
) Error!void {
    if (destination.len < layout.linearBytes()) return error.DestinationTooSmall;

    var y: u32 = 0;
    while (y < layout.height_blocks) : (y += 1) {
        var x: u32 = 0;
        while (x < layout.width_blocks) : (x += 1) {
            const from = offsetFn(x, y, layout.pitch_blocks, layout.block_bytes);
            if (from + layout.block_bytes > source.len) return error.SourceTooSmall;
            const to = (@as(u64, y) * layout.width_blocks + x) * layout.block_bytes;
            @memcpy(
                destination[@intCast(to)..][0..layout.block_bytes],
                source[@intCast(from)..][0..layout.block_bytes],
            );
        }
    }
}

/// A row-major offset, for testing the walk without the real swizzle.
pub fn linearOffset(x: u32, y: u32, pitch: u32, block_bytes: u32) u64 {
    return (@as(u64, y) * pitch + x) * block_bytes;
}

test "an uncompressed layout is one block per texel" {
    const layout = try layoutFor(.r8g8b8a8, 256, 256);
    try std.testing.expectEqual(@as(u32, 256), layout.width_blocks);
    try std.testing.expectEqual(@as(u32, 256), layout.height_blocks);
    try std.testing.expectEqual(@as(u32, 4), layout.block_bytes);
    try std.testing.expectEqual(@as(u64, 256 * 256 * 4), layout.linearBytes());
}

test "a compressed layout is a sixteenth of the texels" {
    const layout = try layoutFor(.dxt1, 256, 256);
    try std.testing.expectEqual(@as(u32, 64), layout.width_blocks);
    try std.testing.expectEqual(@as(u32, 64), layout.height_blocks);
    try std.testing.expectEqual(@as(u32, 8), layout.block_bytes);
    try std.testing.expectEqual(@as(u64, 64 * 64 * 8), layout.linearBytes());
}

test "the tiled size exceeds the linear size when the pitch rounds up" {
    // Sizing a tiled surface with the linear number is how a texture read runs
    // off its own allocation — silently, because the overread is usually
    // still mapped.
    const layout = try layoutFor(.r8g8b8a8, 100, 100);
    try std.testing.expectEqual(@as(u32, 100), layout.width_blocks);
    try std.testing.expectEqual(@as(u32, 128), layout.pitch_blocks);
    try std.testing.expect(layout.tiledBytes() > layout.linearBytes());
    try std.testing.expectEqual(@as(u64, 128 * 100 * 4), layout.tiledBytes());
}

test "an aligned pitch leaves the two sizes equal" {
    const layout = try layoutFor(.r8g8b8a8, 128, 128);
    try std.testing.expectEqual(layout.linearBytes(), layout.tiledBytes());
}

test "a degenerate or unsupported extent is refused" {
    try std.testing.expectError(error.DegenerateExtent, layoutFor(.r8g8b8a8, 0, 16));
    try std.testing.expectError(error.DegenerateExtent, layoutFor(.r8g8b8a8, 16, 0));
    const reserved: contract.TextureFormat = @enumFromInt(200);
    try std.testing.expectError(error.UnsupportedFormat, layoutFor(reserved, 16, 16));
}

test "a mip chain bottoms out at one, not at zero" {
    // A level computing to zero makes every size below it zero, and the tail
    // of the chain silently disappears.
    try std.testing.expectEqual(@as(u32, 256), mipExtent(256, 0));
    try std.testing.expectEqual(@as(u32, 128), mipExtent(256, 1));
    try std.testing.expectEqual(@as(u32, 1), mipExtent(256, 8));
    try std.testing.expectEqual(@as(u32, 1), mipExtent(256, 9));
    try std.testing.expectEqual(@as(u32, 1), mipExtent(256, 100));
    try std.testing.expectEqual(@as(u32, 1), mipExtent(1, 0));
}

test "mip level counts include the base and the 1x1" {
    try std.testing.expectEqual(@as(u32, 1), mipLevelCount(1, 1));
    try std.testing.expectEqual(@as(u32, 2), mipLevelCount(2, 2));
    try std.testing.expectEqual(@as(u32, 9), mipLevelCount(256, 256));
    // A non-square texture chains on its longest edge.
    try std.testing.expectEqual(@as(u32, 9), mipLevelCount(256, 4));
}

test "the untile walk copies every block into row major order" {
    // Using a linear offset function so the walk is tested independently of
    // the reverse-engineered swizzle.
    const layout = try layoutFor(.r8g8b8a8, 2, 2);
    // Pitch rounds to 32 blocks, so the source is 32x2 blocks of 4 bytes.
    var source: [32 * 2 * 4]u8 = @splat(0);
    // Block (0,0) = 0xAA, (1,0) = 0xBB, (0,1) = 0xCC, (1,1) = 0xDD.
    @memset(source[0..4], 0xAA);
    @memset(source[4..8], 0xBB);
    @memset(source[32 * 4 ..][0..4], 0xCC);
    @memset(source[32 * 4 + 4 ..][0..4], 0xDD);

    var destination: [2 * 2 * 4]u8 = undefined;
    try untile(layout, &source, &destination, linearOffset);
    try std.testing.expectEqual(@as(u8, 0xAA), destination[0]);
    try std.testing.expectEqual(@as(u8, 0xBB), destination[4]);
    try std.testing.expectEqual(@as(u8, 0xCC), destination[8]);
    try std.testing.expectEqual(@as(u8, 0xDD), destination[12]);
}

test "an undersized destination is refused before any copy" {
    const layout = try layoutFor(.r8g8b8a8, 4, 4);
    const source = [_]u8{0} ** 4096;
    var destination: [4]u8 = undefined;
    try std.testing.expectError(
        error.DestinationTooSmall,
        untile(layout, &source, &destination, linearOffset),
    );
}

test "a source that cannot hold the tiled surface is refused, not read past" {
    // The overread this guards is usually still mapped memory, so without the
    // check it produces a texture with garbage in its right-hand columns.
    const layout = try layoutFor(.r8g8b8a8, 4, 4);
    const source = [_]u8{0} ** 16;
    var destination: [4 * 4 * 4]u8 = undefined;
    try std.testing.expectError(
        error.SourceTooSmall,
        untile(layout, &source, &destination, linearOffset),
    );
}
