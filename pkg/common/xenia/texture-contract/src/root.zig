//! Route-independent: Xenos texture block geometry, tiling rules, and the
//! channel swizzles the fetch constant selects.
//!
//! These are properties of the console's texture units and of the on-disc data
//! a title ships. One copy, no route mirror.
//!
//! ## The two traps this package exists for
//!
//! **Block geometry.** A compressed format is addressed in 4x4 blocks, an
//! uncompressed one in single texels. Code that computes a size in texels for a
//! DXT surface overestimates by sixteen and reads far past the end; code that
//! computes it in blocks for an uncompressed surface underestimates by the same
//! factor and renders the top-left sixteenth of the image stretched. Both are
//! silent.
//!
//! **Format ordinals are per-enum.** The console has more than one format
//! enumeration and they overlap numerically without agreeing. Ordinal 61 is
//! `dxt3a_as_1` in the texture table and a 2:10:10:10 front-buffer format in
//! the swap table that `lib/gpu/xenos_texture.zig` uses. A number carried from
//! one to the other decodes a compressed texture as if it were 32-bit colour.
//! `TextureFormat` here is *only* the texture table, and the tests below pin
//! the ordinals that make that unambiguous.
//!
//! ## What this package is not
//!
//! * It is not a texture cache. It holds no texels and no residency state;
//!   `lib/gpu/texture_cache/` owns both.
//! * It does not convert anything. The Xenos-to-host format mapping, including
//!   every Vulkan format number, stays in `lib/gpu/xenos_formats.zig` — a host
//!   API's numbering is not a console fact and does not belong here.
//! * It does not untile a surface. `lib/gpu/xenos_texture.zig` owns the address
//!   arithmetic; this package owns only the constants that arithmetic obeys.

const std = @import("std");

// ---------------------------------------------------------------------------
// Tiling
// ---------------------------------------------------------------------------

/// Blocks along one edge of a tile. A surface pitch is rounded up to this, so a
/// 1152-block-wide surface keeps a 1152 pitch and a 1153-wide one becomes 1184.
pub const tile_edge_blocks: u32 = 32;

/// Compressed formats are 4x4. Every one of them, without exception.
pub const compressed_block_edge: u32 = 4;

/// Round a pitch up to the tile edge.
///
/// `tile_edge_blocks` is a power of two, so the mask form is correct here — it
/// is written as a mask deliberately, to match the hardware's rounding rather
/// than a division that a later reader might "simplify" into truncation.
pub fn alignPitch(pitch_blocks: u32) u32 {
    return (pitch_blocks + (tile_edge_blocks - 1)) & ~(tile_edge_blocks - 1);
}

// ---------------------------------------------------------------------------
// Swizzle
// ---------------------------------------------------------------------------

/// The channel swizzle the fetch constant applies as the GPU reads a surface.
///
/// The console is big-endian and this is applied *on top* of that. Choosing the
/// wrong one of the four gives a picture with red and blue exchanged — an image
/// that plainly rendered, which is why it gets attributed to a shader.
pub const Endian = enum(u3) {
    none = 0,
    @"8in16" = 1,
    @"8in32" = 2,
    @"16in32" = 3,

    pub fn apply(self: Endian, value: u32) u32 {
        return switch (self) {
            .none => value,
            .@"8in16" => ((value & 0x00FF00FF) << 8) | ((value & 0xFF00FF00) >> 8),
            .@"8in32" => @byteSwap(value),
            .@"16in32" => (value << 16) | (value >> 16),
        };
    }
};

// ---------------------------------------------------------------------------
// Format table
// ---------------------------------------------------------------------------

/// The Xenos *texture* fetch format table.
///
/// Non-exhaustive: the hardware has reserved ordinals, and a title that fetches
/// with one must not trap a cast here. `blockGeometryOf` reports the unknown
/// rather than guessing a size for it.
pub const TextureFormat = enum(u8) {
    one_reverse = 0,
    one = 1,
    r8 = 2,
    a1r5g5b5 = 3,
    r5g6b5 = 4,
    a6b5g5r5 = 5,
    r8g8b8a8 = 6,
    a2r10g10b10 = 7,
    a8 = 8,
    b8 = 9,
    r8g8 = 10,
    cr_y1_cb_y0 = 11,
    y1_cr_y0_cb = 12,
    r16g16_edram = 13,
    r8g8b8a8_a = 14,
    a4r4g4b4 = 15,
    r10g11b11 = 16,
    r11g11b10 = 17,
    dxt1 = 18,
    dxt2_3 = 19,
    dxt4_5 = 20,
    r16g16b16a16_edram = 21,
    d24s8 = 22,
    d24fs8 = 23,
    r16 = 24,
    r16g16 = 25,
    r16g16b16a16 = 26,
    r16_expand = 27,
    r16g16_expand = 28,
    r16g16b16a16_expand = 29,
    r16_float = 30,
    r16g16_float = 31,
    r16g16b16a16_float = 32,
    r32 = 33,
    r32g32 = 34,
    r32g32b32a32 = 35,
    r32_float = 36,
    r32g32_float = 37,
    r32g32b32a32_float = 38,
    r32_as_8 = 39,
    r32_as_8_8 = 40,
    r16_mpeg = 41,
    r16g16_mpeg = 42,
    r8_interlaced = 43,
    r32_as_8_interlaced = 44,
    r32_as_8_8_interlaced = 45,
    r16_interlaced = 46,
    r16_mpeg_interlaced = 47,
    r16g16_mpeg_interlaced = 48,
    dxn = 49,
    r8g8b8a8_as_16 = 50,
    dxt1_as_16 = 51,
    dxt2_3_as_16 = 52,
    dxt4_5_as_16 = 53,
    a2r10g10b10_as_16 = 54,
    r10g11b11_as_16 = 55,
    r11g11b10_as_16 = 56,
    r32g32b32_float = 57,
    dxt3a = 58,
    dxt5a = 59,
    ctx1 = 60,
    dxt3a_as_1 = 61,
    r8g8b8a8_gamma_edram = 62,
    a2r10g10b10_float_edram = 63,
    _,
};

pub const BlockGeometry = struct {
    block_width: u32,
    block_height: u32,
    /// Bytes one block occupies. For an uncompressed format a "block" is one
    /// texel, so this is bytes per texel.
    block_bytes: u32,
    compressed: bool,

    pub fn texelsPerBlock(self: BlockGeometry) u32 {
        return self.block_width * self.block_height;
    }
};

/// Block geometry for a format, or null when the ordinal is one the hardware
/// reserves.
///
/// Null is the honest answer for a reserved ordinal. Returning a plausible
/// default instead is how an unknown format becomes a silently wrong size.
pub fn blockGeometryOf(format: TextureFormat) ?BlockGeometry {
    return switch (format) {
        // 4x4 compressed, 8 bytes per block: one colour block.
        .dxt1, .dxt1_as_16, .dxt3a, .dxt5a, .dxt3a_as_1, .ctx1 => .{
            .block_width = 4,
            .block_height = 4,
            .block_bytes = 8,
            .compressed = true,
        },
        // 4x4 compressed, 16 bytes per block: colour plus alpha, or two
        // channels for DXN.
        .dxt2_3, .dxt2_3_as_16, .dxt4_5, .dxt4_5_as_16, .dxn => .{
            .block_width = 4,
            .block_height = 4,
            .block_bytes = 16,
            .compressed = true,
        },
        // Sub-byte formats. One bit per texel, so a block is eight texels
        // wide; they are not "compressed" in the DXT sense.
        .one, .one_reverse => .{
            .block_width = 8,
            .block_height = 1,
            .block_bytes = 1,
            .compressed = false,
        },
        .r8, .a8, .b8, .r8_interlaced => uncompressed(1),
        .a1r5g5b5, .r5g6b5, .a6b5g5r5, .a4r4g4b4, .r8g8, .r16, .r16_expand,
        .r16_float, .r16_mpeg, .r16_interlaced, .r16_mpeg_interlaced,
        .cr_y1_cb_y0, .y1_cr_y0_cb => uncompressed(2),
        .r8g8b8a8, .r8g8b8a8_a, .r8g8b8a8_as_16, .r8g8b8a8_gamma_edram,
        .a2r10g10b10, .a2r10g10b10_as_16, .a2r10g10b10_float_edram,
        .r10g11b11, .r10g11b11_as_16, .r11g11b10, .r11g11b10_as_16,
        .d24s8, .d24fs8, .r16g16, .r16g16_expand, .r16g16_float,
        .r16g16_edram, .r16g16_mpeg, .r16g16_mpeg_interlaced,
        .r32, .r32_float, .r32_as_8, .r32_as_8_8,
        .r32_as_8_interlaced, .r32_as_8_8_interlaced => uncompressed(4),
        .r16g16b16a16, .r16g16b16a16_expand, .r16g16b16a16_float,
        .r16g16b16a16_edram, .r32g32, .r32g32_float => uncompressed(8),
        .r32g32b32_float => uncompressed(12),
        .r32g32b32a32, .r32g32b32a32_float => uncompressed(16),
        _ => null,
    };
}

fn uncompressed(bytes: u32) BlockGeometry {
    return .{ .block_width = 1, .block_height = 1, .block_bytes = bytes, .compressed = false };
}

/// Blocks needed to cover a texel extent, rounding up.
///
/// A partial block is a whole block. Truncating loses the right or bottom edge
/// of every non-multiple-of-four texture, which reads as a one-texel seam.
pub fn blocksForExtent(texels: u32, block_edge: u32) u32 {
    if (block_edge == 0) return 0;
    return (texels + block_edge - 1) / block_edge;
}

/// Bytes an untiled mip level of this shape occupies.
///
/// Returns null for a reserved format rather than a wrong number.
pub fn linearLevelBytes(format: TextureFormat, width: u32, height: u32) ?u64 {
    const geometry = blockGeometryOf(format) orelse return null;
    const across = blocksForExtent(width, geometry.block_width);
    const down = blocksForExtent(height, geometry.block_height);
    return @as(u64, across) * down * geometry.block_bytes;
}

pub fn contractIsWellFormed() bool {
    if (!std.math.isPowerOfTwo(tile_edge_blocks)) return false;
    if (compressed_block_edge != 4) return false;
    if (alignPitch(0) != 0) return false;
    return true;
}

test "the contract is internally consistent" {
    try std.testing.expect(contractIsWellFormed());
}

test "every compressed format is four by four" {
    // No exceptions. A format that reported 8x8 would silently quarter a
    // surface's size and read a quarter of the data.
    const compressed = [_]TextureFormat{
        .dxt1, .dxt2_3, .dxt4_5, .dxn, .dxt3a, .dxt5a, .ctx1,
        .dxt1_as_16, .dxt2_3_as_16, .dxt4_5_as_16, .dxt3a_as_1,
    };
    for (compressed) |format| {
        const geometry = blockGeometryOf(format).?;
        try std.testing.expect(geometry.compressed);
        try std.testing.expectEqual(compressed_block_edge, geometry.block_width);
        try std.testing.expectEqual(compressed_block_edge, geometry.block_height);
        try std.testing.expectEqual(@as(u32, 16), geometry.texelsPerBlock());
    }
}

test "DXT1 is half the size of DXT5 for the same extent" {
    // 8 vs 16 bytes per block. Getting these equal is the classic way a BC1
    // surface reads at twice its stride and shears.
    try std.testing.expectEqual(@as(u32, 8), blockGeometryOf(.dxt1).?.block_bytes);
    try std.testing.expectEqual(@as(u32, 16), blockGeometryOf(.dxt4_5).?.block_bytes);
    const bc1 = linearLevelBytes(.dxt1, 256, 256).?;
    const bc3 = linearLevelBytes(.dxt4_5, 256, 256).?;
    try std.testing.expectEqual(bc1 * 2, bc3);
    // 256x256 DXT1 is 64x64 blocks of 8 bytes.
    try std.testing.expectEqual(@as(u64, 64 * 64 * 8), bc1);
}

test "ordinal 61 is a compressed texture format, not a colour format" {
    // The overlap that costs the most: in lib/gpu/xenos_texture.zig's *swap*
    // table 61 names a 2:10:10:10 front-buffer format. Here it is dxt3a_as_1.
    // A number carried across the two decodes a compressed texture as 32-bit
    // colour, and the result is a picture, so nothing reports an error.
    try std.testing.expectEqual(@as(u8, 61), @intFromEnum(TextureFormat.dxt3a_as_1));
    try std.testing.expect(blockGeometryOf(.dxt3a_as_1).?.compressed);
    // 54 is where 2:10:10:10-as-16 actually lives in *this* table.
    try std.testing.expectEqual(@as(u8, 54), @intFromEnum(TextureFormat.a2r10g10b10_as_16));
    try std.testing.expect(!blockGeometryOf(.a2r10g10b10_as_16).?.compressed);
}

test "the ordinals match the table lib/gpu/xenos_formats.zig carries" {
    // Pinned so the two tables cannot drift apart unnoticed.
    try std.testing.expectEqual(@as(u8, 6), @intFromEnum(TextureFormat.r8g8b8a8));
    try std.testing.expectEqual(@as(u8, 18), @intFromEnum(TextureFormat.dxt1));
    try std.testing.expectEqual(@as(u8, 49), @intFromEnum(TextureFormat.dxn));
    try std.testing.expectEqual(@as(u8, 58), @intFromEnum(TextureFormat.dxt3a));
    try std.testing.expectEqual(@as(u8, 59), @intFromEnum(TextureFormat.dxt5a));
    try std.testing.expectEqual(@as(u8, 60), @intFromEnum(TextureFormat.ctx1));
    try std.testing.expectEqual(@as(u8, 63), @intFromEnum(TextureFormat.a2r10g10b10_float_edram));
}

test "a reserved ordinal reports unknown instead of guessing" {
    // The honest answer. A default geometry here would turn an unsupported
    // fetch into a plausible wrong size and a read past the surface.
    const reserved: TextureFormat = @enumFromInt(200);
    try std.testing.expect(blockGeometryOf(reserved) == null);
    try std.testing.expect(linearLevelBytes(reserved, 64, 64) == null);
}

test "pitch alignment rounds up to the tile edge and leaves exact pitches alone" {
    // The example from the hardware's own behaviour: 1152 is already aligned,
    // 1153 goes to 1184.
    try std.testing.expectEqual(@as(u32, 1152), alignPitch(1152));
    try std.testing.expectEqual(@as(u32, 1184), alignPitch(1153));
    try std.testing.expectEqual(@as(u32, 32), alignPitch(1));
    try std.testing.expectEqual(@as(u32, 32), alignPitch(32));
    try std.testing.expectEqual(@as(u32, 64), alignPitch(33));
    try std.testing.expectEqual(@as(u32, 0), alignPitch(0));
}

test "a partial block is a whole block" {
    try std.testing.expectEqual(@as(u32, 1), blocksForExtent(1, 4));
    try std.testing.expectEqual(@as(u32, 1), blocksForExtent(4, 4));
    try std.testing.expectEqual(@as(u32, 2), blocksForExtent(5, 4));
    // A 63x63 DXT1 texture still needs 16x16 blocks, not 15x15.
    try std.testing.expectEqual(@as(u32, 16), blocksForExtent(63, 4));
    try std.testing.expectEqual(@as(u64, 16 * 16 * 8), linearLevelBytes(.dxt1, 63, 63).?);
}

test "uncompressed formats are one texel per block" {
    const rgba = blockGeometryOf(.r8g8b8a8).?;
    try std.testing.expect(!rgba.compressed);
    try std.testing.expectEqual(@as(u32, 1), rgba.texelsPerBlock());
    try std.testing.expectEqual(@as(u32, 4), rgba.block_bytes);
    // 256x256 at four bytes a texel.
    try std.testing.expectEqual(@as(u64, 256 * 256 * 4), linearLevelBytes(.r8g8b8a8, 256, 256).?);
}

test "one-bit formats pack eight texels to the byte" {
    const mono = blockGeometryOf(.one).?;
    try std.testing.expectEqual(@as(u32, 8), mono.block_width);
    try std.testing.expectEqual(@as(u32, 1), mono.block_height);
    try std.testing.expectEqual(@as(u32, 1), mono.block_bytes);
    // Not DXT-compressed, despite covering more than one texel per block.
    try std.testing.expect(!mono.compressed);
    try std.testing.expectEqual(@as(u64, 8), linearLevelBytes(.one, 64, 1).?);
}

test "the swizzles are involutions where the hardware says they are" {
    // Each of these swaps units of equal size, so applying one twice is the
    // identity. A swizzle that failed this would be corrupting, not permuting.
    const sample: u32 = 0x11223344;
    try std.testing.expectEqual(sample, Endian.none.apply(sample));
    try std.testing.expectEqual(sample, Endian.@"8in16".apply(Endian.@"8in16".apply(sample)));
    try std.testing.expectEqual(sample, Endian.@"8in32".apply(Endian.@"8in32".apply(sample)));
    try std.testing.expectEqual(sample, Endian.@"16in32".apply(Endian.@"16in32".apply(sample)));
}

test "the swizzles permute the bytes they claim to" {
    const sample: u32 = 0x11223344;
    try std.testing.expectEqual(@as(u32, 0x22114433), Endian.@"8in16".apply(sample));
    try std.testing.expectEqual(@as(u32, 0x44332211), Endian.@"8in32".apply(sample));
    try std.testing.expectEqual(@as(u32, 0x33441122), Endian.@"16in32".apply(sample));
}
