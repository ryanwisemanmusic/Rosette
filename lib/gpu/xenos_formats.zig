//! Xenos texture, render-target, and vertex-format metadata.
//!
//! Xbox 360 format numbers are not Vulkan format numbers.  Keeping the table
//! in one place prevents a format from being treated as four bytes per pixel in
//! one path and as a compressed block in another.  The table is also useful to
//! the CPU front-buffer converter and to the Vulkan marshaller, so neither has
//! to guess from an enum value.

const std = @import("std");
const abi = @import("vulkan/abi.zig");
const texture_layout = @import("xenos_texture.zig");

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
    r32g32g32_float = 57,
    dxt3a = 58,
    dxt5a = 59,
    ctx1 = 60,
    dxt3a_as_1 = 61,
    r8g8b8a8_gamma_edram = 62,
    a2r10g10b10_float_edram = 63,
    _,
};

pub const VertexFormat = enum(u8) {
    undefined = 0,
    r8g8b8a8 = 6,
    a2r10g10b10 = 7,
    r10g11b11 = 16,
    r11g11b10 = 17,
    r16g16 = 25,
    r16g16b16a16 = 26,
    r16g16_float = 31,
    r16g16b16a16_float = 32,
    r32 = 33,
    r32g32 = 34,
    r32g32b32a32 = 35,
    r32_float = 36,
    r32g32_float = 37,
    r32g32b32a32_float = 38,
    r32g32b32_float = 57,
    _,
};

pub const Dimension = enum(u2) {
    one_d = 0,
    two_d = 1,
    three_d = 2,
    cube = 3,
};

pub const Tiling = enum(u1) {
    linear = 0,
    tiled = 1,
};

pub const Info = struct {
    bytes_per_pixel: u8 = 0,
    block_width: u8 = 1,
    block_height: u8 = 1,
    block_bytes: u8 = 0,
    vulkan_format: u32 = abi.FORMAT_UNDEFINED,
    depth: bool = false,
    stencil: bool = false,
    compressed: bool = false,
    srgb: bool = false,
    renderable: bool = false,

    pub fn bytesPerBlock(self: Info) u32 {
        return if (self.compressed) self.block_bytes else self.bytes_per_pixel;
    }
};

pub fn info(format: TextureFormat) Info {
    return switch (format) {
        .one_reverse, .one => .{ .bytes_per_pixel = 1 },
        .r8, .a8, .b8 => .{ .bytes_per_pixel = 1, .vulkan_format = abi.FORMAT_R8_UNORM },
        .a1r5g5b5 => .{ .bytes_per_pixel = 2, .vulkan_format = abi.FORMAT_A1R5G5B5_UNORM_PACK16 },
        .r5g6b5 => .{ .bytes_per_pixel = 2, .vulkan_format = abi.FORMAT_R5G6B5_UNORM_PACK16 },
        .a6b5g5r5 => .{ .bytes_per_pixel = 2, .vulkan_format = abi.FORMAT_R5G6B5_UNORM_PACK16 },
        .r8g8b8a8, .r8g8b8a8_a, .r8g8b8a8_gamma_edram => .{
            .bytes_per_pixel = 4,
            .vulkan_format = abi.FORMAT_R8G8B8A8_UNORM,
            .renderable = true,
            .srgb = format == .r8g8b8a8_gamma_edram,
        },
        .a2r10g10b10, .a2r10g10b10_as_16, .a2r10g10b10_float_edram => .{
            .bytes_per_pixel = 4,
            .vulkan_format = abi.FORMAT_A2B10G10R10_UNORM_PACK32,
            .renderable = true,
        },
        .r8g8 => .{ .bytes_per_pixel = 2, .vulkan_format = abi.FORMAT_R8G8_UNORM },
        .a4r4g4b4 => .{ .bytes_per_pixel = 2, .vulkan_format = abi.FORMAT_B4G4R4A4_UNORM_PACK16 },
        .r10g11b11 => .{ .bytes_per_pixel = 4, .vulkan_format = abi.FORMAT_R16G16B16A16_UNORM },
        .r11g11b10 => .{ .bytes_per_pixel = 4, .vulkan_format = abi.FORMAT_R16G16B16A16_UNORM },
        .dxt1, .dxt1_as_16 => .{ .block_width = 4, .block_height = 4, .block_bytes = 8, .vulkan_format = abi.FORMAT_BC1_RGBA_UNORM_BLOCK, .compressed = true },
        .dxt2_3, .dxt2_3_as_16 => .{ .block_width = 4, .block_height = 4, .block_bytes = 16, .vulkan_format = abi.FORMAT_BC2_UNORM_BLOCK, .compressed = true },
        .dxt4_5, .dxt4_5_as_16 => .{ .block_width = 4, .block_height = 4, .block_bytes = 16, .vulkan_format = abi.FORMAT_BC3_UNORM_BLOCK, .compressed = true },
        .dxn => .{ .block_width = 4, .block_height = 4, .block_bytes = 16, .vulkan_format = abi.FORMAT_BC5_UNORM_BLOCK, .compressed = true },
        .ctx1 => .{ .block_width = 4, .block_height = 4, .block_bytes = 8, .vulkan_format = abi.FORMAT_R8G8_UNORM, .compressed = true },
        .dxt3a => .{ .block_width = 4, .block_height = 4, .block_bytes = 8, .vulkan_format = abi.FORMAT_R8_UNORM, .compressed = true },
        .dxt5a => .{ .block_width = 4, .block_height = 4, .block_bytes = 8, .vulkan_format = abi.FORMAT_BC4_UNORM_BLOCK, .compressed = true },
        .dxt3a_as_1 => .{ .block_width = 4, .block_height = 4, .block_bytes = 8, .vulkan_format = abi.FORMAT_B4G4R4A4_UNORM_PACK16, .compressed = true },
        .r16, .r16_expand => .{ .bytes_per_pixel = 2, .vulkan_format = abi.FORMAT_R16_UNORM },
        .r16g16, .r16g16_expand => .{ .bytes_per_pixel = 4, .vulkan_format = abi.FORMAT_R16G16_UNORM },
        .r16g16b16a16, .r16g16b16a16_expand => .{ .bytes_per_pixel = 8, .vulkan_format = abi.FORMAT_R16G16B16A16_UNORM },
        .r16_float => .{ .bytes_per_pixel = 2, .vulkan_format = abi.FORMAT_R16_SFLOAT },
        .r16g16_float => .{ .bytes_per_pixel = 4, .vulkan_format = abi.FORMAT_R16G16_SFLOAT },
        .r16g16b16a16_float => .{ .bytes_per_pixel = 8, .vulkan_format = abi.FORMAT_R16G16B16A16_SFLOAT },
        .r32 => .{ .bytes_per_pixel = 4 },
        .r32g32 => .{ .bytes_per_pixel = 8 },
        .r32g32b32a32 => .{ .bytes_per_pixel = 16 },
        .r32_float => .{ .bytes_per_pixel = 4, .vulkan_format = abi.FORMAT_R32_SFLOAT },
        .r32g32_float => .{ .bytes_per_pixel = 8, .vulkan_format = abi.FORMAT_R32G32_SFLOAT },
        .r32g32b32a32_float => .{ .bytes_per_pixel = 16, .vulkan_format = abi.FORMAT_R32G32B32A32_SFLOAT },
        .r32g32g32_float => .{ .bytes_per_pixel = 12 },
        .d24s8, .d24fs8 => .{ .bytes_per_pixel = 4, .vulkan_format = abi.FORMAT_R32_SFLOAT, .depth = true, .stencil = true },
        .r16_mpeg, .r16_interlaced, .r16_mpeg_interlaced => .{ .bytes_per_pixel = 2 },
        .r16g16_mpeg, .r16g16_mpeg_interlaced => .{ .bytes_per_pixel = 4 },
        .r8_interlaced => .{ .bytes_per_pixel = 1, .vulkan_format = abi.FORMAT_R8_UNORM },
        .r32_as_8, .r32_as_8_interlaced => .{ .bytes_per_pixel = 4, .vulkan_format = abi.FORMAT_R8G8B8A8_UNORM },
        .r32_as_8_8, .r32_as_8_8_interlaced => .{ .bytes_per_pixel = 4, .vulkan_format = abi.FORMAT_R8G8B8A8_UNORM },
        .cr_y1_cb_y0 => .{ .bytes_per_pixel = 4, .vulkan_format = abi.FORMAT_G8B8G8R8_422_UNORM },
        .y1_cr_y0_cb => .{ .bytes_per_pixel = 4, .vulkan_format = abi.FORMAT_B8G8R8G8_422_UNORM },
        .r16g16_edram => .{ .bytes_per_pixel = 4 },
        .r16g16b16a16_edram => .{ .bytes_per_pixel = 8 },
        .r10g11b11_as_16, .r11g11b10_as_16 => .{ .bytes_per_pixel = 4, .vulkan_format = abi.FORMAT_R16G16B16A16_UNORM },
        else => .{},
    };
}

pub fn textureInfo(raw_format: u32) Info {
    return info(@enumFromInt(@as(u8, @truncate(raw_format))));
}

pub fn toVulkanFormat(raw_format: u32) ?u32 {
    const value = info(@enumFromInt(@as(u8, @truncate(raw_format))));
    return if (value.vulkan_format == abi.FORMAT_UNDEFINED) null else value.vulkan_format;
}

/// Map RB_COLOR_INFO's ColorRenderTargetFormat values.  These values share
/// the numeric space of texture formats only for a few entries; using
/// `toVulkanFormat` here turns 16_16 and 2_10_10_10 targets into unrelated
/// texture formats.  The table mirrors Xenia's Vulkan render-target cache.
pub fn renderTargetVulkanFormat(raw_format: u32) ?u32 {
    return switch (raw_format & 0x1F) {
        0 => abi.FORMAT_R8G8B8A8_UNORM,
        1 => abi.FORMAT_R8G8B8A8_SRGB,
        2, 10 => abi.FORMAT_A8B8G8R8_UNORM_PACK32,
        3, 7, 12 => abi.FORMAT_R16G16B16A16_SFLOAT,
        4 => abi.FORMAT_R16G16_SNORM,
        5 => abi.FORMAT_R16G16B16A16_SNORM,
        6 => abi.FORMAT_R16G16_SFLOAT,
        14 => abi.FORMAT_R32_SFLOAT,
        15 => abi.FORMAT_R32G32_SFLOAT,
        else => null,
    };
}

pub fn bytesForExtent(raw_format: u32, width: u32, height: u32, depth: u32) ?u64 {
    const value = textureInfo(raw_format);
    if (value.bytesPerBlock() == 0 or width == 0 or height == 0 or depth == 0) return null;
    const blocks_x = (@as(u64, width) + value.block_width - 1) / value.block_width;
    const blocks_y = (@as(u64, height) + value.block_height - 1) / value.block_height;
    const block_count = std.math.mul(u64, blocks_x, blocks_y) catch return null;
    const depth_count = std.math.mul(u64, block_count, depth) catch return null;
    return std.math.mul(u64, depth_count, value.bytesPerBlock()) catch null;
}

pub fn mipExtent(width: u32, height: u32, depth: u32, level: u32) struct { width: u32, height: u32, depth: u32 } {
    return .{
        .width = @max(width >> @min(level, 31), 1),
        .height = @max(height >> @min(level, 31), 1),
        .depth = @max(depth >> @min(level, 31), 1),
    };
}

pub const SurfaceLayout = struct {
    row_pitch: u64,
    slice_pitch: u64,
    size_bytes: u64,
};

pub fn layout(raw_format: u32, width: u32, height: u32, depth: u32, tiling: Tiling) ?SurfaceLayout {
    const value = textureInfo(raw_format);
    if (value.bytesPerBlock() == 0 or width == 0 or height == 0 or depth == 0) return null;
    const blocks_x = (@as(u64, width) + value.block_width - 1) / value.block_width;
    const blocks_y = (@as(u64, height) + value.block_height - 1) / value.block_height;
    const raw_pitch = blocks_x * value.bytesPerBlock();
    const row_pitch = if (tiling == .linear) std.mem.alignForward(u64, raw_pitch, 256) else raw_pitch;
    const slice_pitch = if (tiling == .tiled and
        value.bytesPerBlock() & (value.bytesPerBlock() - 1) == 0 and
        blocks_x <= std.math.maxInt(u32) and blocks_y <= std.math.maxInt(u32))
    blk: {
        const block_log2: u5 = @intCast(@ctz(value.bytesPerBlock()));
        break :blk texture_layout.tiledAddressUpperBound2D(
            @intCast(blocks_x),
            @intCast(blocks_y),
            @intCast(blocks_x),
            block_log2,
        );
    } else row_pitch * blocks_y;
    const size_bytes = std.math.mul(u64, slice_pitch, depth) catch return null;
    return .{ .row_pitch = row_pitch, .slice_pitch = slice_pitch, .size_bytes = size_bytes };
}

/// Whether a vertex stream's components are signed.
///
/// A property of the shader's `vfetch` instruction (`fomat_comp_all`), not of
/// the fetch constant, so it has to travel with the format rather than be
/// derived from it.
pub const VertexSignedness = enum { unsigned, signed };

/// The host vertex format for a Xenos vertex format and its signedness.
///
/// The signedness is not optional detail. A signed normalized stream fed
/// through the unsigned host format reads every negative component as a large
/// positive one — the same reinterpretation the texture-format contract exists
/// to refuse — and it is exactly what this function did for every caller
/// before it could be told.
///
/// `A2B10G10R10_SNORM_PACK32` is the case that matters most here. It is
/// unusable as an image on Metal (both tiling feature fields read zero) and
/// *natively supported as a vertex attribute* — the driver reports
/// `VERTEX_BUFFER_BIT` for it, backed by
/// `MTLVertexFormatInt1010102Normalized`. So the signed 2:10:10:10 vertex path
/// needs no substitution at all; it needed only to be asked for.
pub fn vertexVulkanFormatSigned(raw_format: u32, signedness: VertexSignedness) ?u32 {
    if (signedness == .signed) {
        const format: VertexFormat = @enumFromInt(@as(u8, @truncate(raw_format)));
        // Only the normalized integer formats have a signed twin. The float
        // and raw-integer formats already carry their own sign and fall
        // through to the unsigned table unchanged.
        switch (format) {
            .r8g8b8a8 => return abi.FORMAT_R8G8B8A8_SNORM,
            .a2r10g10b10 => return abi.FORMAT_A2B10G10R10_SNORM_PACK32,
            .r16g16 => return abi.FORMAT_R16G16_SNORM,
            .r16g16b16a16 => return abi.FORMAT_R16G16B16A16_SNORM,
            else => {},
        }
    }
    return vertexVulkanFormat(raw_format);
}

pub fn vertexVulkanFormat(raw_format: u32) ?u32 {
    const format: VertexFormat = @enumFromInt(@as(u8, @truncate(raw_format)));
    return switch (format) {
        .r8g8b8a8 => abi.FORMAT_R8G8B8A8_UNORM,
        .a2r10g10b10 => abi.FORMAT_A2B10G10R10_UNORM_PACK32,
        .r16g16 => abi.FORMAT_R16G16_UNORM,
        .r16g16b16a16 => abi.FORMAT_R16G16B16A16_UNORM,
        .r16g16_float => abi.FORMAT_R16G16_SFLOAT,
        .r16g16b16a16_float => abi.FORMAT_R16G16B16A16_SFLOAT,
        .r32 => abi.FORMAT_R32_SFLOAT,
        .r32g32 => abi.FORMAT_R32G32_SFLOAT,
        .r32g32b32a32 => abi.FORMAT_R32G32B32A32_SFLOAT,
        .r32_float => abi.FORMAT_R32_SFLOAT,
        .r32g32_float => abi.FORMAT_R32G32_SFLOAT,
        .r32g32b32a32_float => abi.FORMAT_R32G32B32A32_SFLOAT,
        .r32g32b32_float => abi.FORMAT_R32G32B32_SFLOAT,
        else => null,
    };
}

test "the Xenos format table distinguishes packed, compressed, depth, and float data" {
    try std.testing.expectEqual(@as(u8, 4), info(.r8g8b8a8).bytesPerBlock());
    try std.testing.expect(info(.dxt1).compressed);
    try std.testing.expectEqual(@as(u8, 8), info(.dxt1).block_bytes);
    try std.testing.expect(info(.d24s8).depth and info(.d24s8).stencil);
    try std.testing.expectEqual(@as(u64, 1280 * 720 * 4), bytesForExtent(6, 1280, 720, 1).?);
}

test "linear layouts align rows and mip extents never become zero" {
    const result = layout(6, 1280, 720, 1, .linear).?;
    try std.testing.expectEqual(@as(u64, 5120), result.row_pitch);
    try std.testing.expectEqual(@as(u64, 5120 * 720), result.size_bytes);
    const mip = mipExtent(1, 1, 1, 12);
    try std.testing.expectEqual(@as(u32, 1), mip.width);
    try std.testing.expectEqual(@as(u32, 1), mip.height);
}

test "tiled layouts use the Xenos swizzle bound instead of scanline sizing" {
    const result = layout(6, 37, 35, 1, .tiled).?;
    const expected = texture_layout.tiledAddressUpperBound2D(37, 35, 37, 2);
    try std.testing.expectEqual(expected, result.slice_pitch);
    try std.testing.expectEqual(expected, result.size_bytes);
    try std.testing.expect(result.size_bytes > @as(u64, 37 * 35 * 4));
}

test "texture mappings match Xenia's active Vulkan host table" {
    try std.testing.expectEqual(abi.FORMAT_A1R5G5B5_UNORM_PACK16, toVulkanFormat(@intFromEnum(TextureFormat.a1r5g5b5)).?);
    try std.testing.expectEqual(abi.FORMAT_B4G4R4A4_UNORM_PACK16, toVulkanFormat(@intFromEnum(TextureFormat.a4r4g4b4)).?);
    try std.testing.expectEqual(abi.FORMAT_BC1_RGBA_UNORM_BLOCK, toVulkanFormat(@intFromEnum(TextureFormat.dxt1)).?);
    try std.testing.expectEqual(abi.FORMAT_BC2_UNORM_BLOCK, toVulkanFormat(@intFromEnum(TextureFormat.dxt2_3)).?);
    try std.testing.expectEqual(abi.FORMAT_BC3_UNORM_BLOCK, toVulkanFormat(@intFromEnum(TextureFormat.dxt4_5)).?);
    try std.testing.expectEqual(abi.FORMAT_BC5_UNORM_BLOCK, toVulkanFormat(@intFromEnum(TextureFormat.dxn)).?);
    try std.testing.expectEqual(abi.FORMAT_R8G8_UNORM, toVulkanFormat(@intFromEnum(TextureFormat.ctx1)).?);
    try std.testing.expectEqual(abi.FORMAT_R16G16_UNORM, toVulkanFormat(@intFromEnum(TextureFormat.r16g16)).?);
    try std.testing.expectEqual(abi.FORMAT_R16G16_SFLOAT, toVulkanFormat(@intFromEnum(TextureFormat.r16g16_float)).?);
    try std.testing.expectEqual(abi.FORMAT_R32G32_SFLOAT, toVulkanFormat(@intFromEnum(TextureFormat.r32g32_float)).?);
    try std.testing.expect(toVulkanFormat(@intFromEnum(TextureFormat.r32g32)) == null);
}

test "render target formats use the Xenos color-target table" {
    try std.testing.expectEqual(abi.FORMAT_R8G8B8A8_UNORM, renderTargetVulkanFormat(0).?);
    try std.testing.expectEqual(abi.FORMAT_R8G8B8A8_SRGB, renderTargetVulkanFormat(1).?);
    try std.testing.expectEqual(abi.FORMAT_A8B8G8R8_UNORM_PACK32, renderTargetVulkanFormat(2).?);
    try std.testing.expectEqual(abi.FORMAT_R16G16_SNORM, renderTargetVulkanFormat(4).?);
    try std.testing.expectEqual(abi.FORMAT_R16G16B16A16_SNORM, renderTargetVulkanFormat(5).?);
    try std.testing.expectEqual(abi.FORMAT_R16G16B16A16_SFLOAT, renderTargetVulkanFormat(7).?);
    try std.testing.expectEqual(abi.FORMAT_R32G32_SFLOAT, renderTargetVulkanFormat(15).?);
    try std.testing.expect(renderTargetVulkanFormat(8) == null);
}

// The 2026-09-03 audit: `A2B10G10R10_SNORM_PACK32` is a native vertex format on
// this host (the driver reports VERTEX_BUFFER_BIT for it) and the mapping could
// not name it, because it had no way to be told the stream was signed. Every
// signed 2:10:10:10 normal or tangent would have gone through the unsigned
// format, reading each negative component as a large positive one.
test "a signed vertex stream names the signed host format" {
    const a2r10g10b10: u32 = 7;
    try std.testing.expectEqual(
        abi.FORMAT_A2B10G10R10_UNORM_PACK32,
        vertexVulkanFormatSigned(a2r10g10b10, .unsigned).?,
    );
    try std.testing.expectEqual(
        abi.FORMAT_A2B10G10R10_SNORM_PACK32,
        vertexVulkanFormatSigned(a2r10g10b10, .signed).?,
    );
    // The other normalized integer formats have signed twins too, and this
    // host supports all of them as vertex attributes.
    try std.testing.expectEqual(abi.FORMAT_R8G8B8A8_SNORM, vertexVulkanFormatSigned(6, .signed).?);
    try std.testing.expectEqual(abi.FORMAT_R16G16_SNORM, vertexVulkanFormatSigned(25, .signed).?);
    try std.testing.expectEqual(abi.FORMAT_R16G16B16A16_SNORM, vertexVulkanFormatSigned(26, .signed).?);
}

// A float format already carries its own sign, so signedness must not move it.
test "signedness leaves the float and unmapped formats alone" {
    for ([_]u32{ 31, 32, 36, 37, 38, 57 }) |raw| {
        try std.testing.expectEqual(
            vertexVulkanFormat(raw),
            vertexVulkanFormatSigned(raw, .signed),
        );
    }
    // An unmapped format is still unmapped, whichever sign it claims.
    try std.testing.expectEqual(@as(?u32, null), vertexVulkanFormatSigned(200, .signed));
    try std.testing.expectEqual(@as(?u32, null), vertexVulkanFormatSigned(200, .unsigned));
}

// The unsigned entry point is what every existing caller uses, and it has to
// keep meaning exactly what it meant.
test "the unsigned entry point is unchanged" {
    try std.testing.expectEqual(
        abi.FORMAT_A2B10G10R10_UNORM_PACK32,
        vertexVulkanFormat(7).?,
    );
}
