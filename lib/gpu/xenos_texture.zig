//! Turning the console's front buffer into pixels a window can show.
//!
//! The last hop of a frame is the one with no error path. A front buffer is a
//! block of console memory, and every fact needed to read it correctly —
//! whether it is tiled, which byte order its dwords are in, which channel is
//! red — lives somewhere other than the buffer. Get any of them wrong and the
//! result is still an image: a diagonally sheared one, a blue-and-orange one, a
//! blocky mosaic. None of those fail, so none of them can be found later by
//! anything except looking at them.
//!
//! So this module states each of the three and converts under exactly those
//! assumptions, and the caller supplies them from the texture fetch constant
//! the swap packet was preceded by rather than guessing.
//!
//! ## Tiling
//!
//! The Xenos stores textures in a 32×32-block swizzle, not in scanline order.
//! The address function is not derivable from first principles — it mixes and
//! re-mixes bit fields of the coordinates — so it is transcribed here from the
//! emulator's own implementation, and tested against the properties that
//! transcription can get wrong: that it is a bijection over a tile, and that it
//! stays inside the surface.
//!
//! A linear surface is the common case for a front buffer that came from a
//! resolve, and a tiled one for a front buffer the title composed itself. Both
//! happen, which is why the flag is a parameter and not a constant.
//!
//! ## Byte order
//!
//! The console is big-endian and the GPU applies a further swizzle described by
//! the fetch constant. Reading a `k_8_8_8_8` surface with the wrong one of the
//! four swizzles gives a picture with the red and blue channels exchanged — the
//! single most common wrong-looking-but-working emulator screenshot there is.

const std = @import("std");

/// The channel swizzle the GPU applies when it reads the surface. Named as the
/// fetch constant names it: `8in16` means bytes are swapped within each 16-bit
/// unit, and so on.
pub const Endian = enum(u3) {
    none = 0,
    @"8in16" = 1,
    @"8in32" = 2,
    @"16in32" = 3,
    _,

    pub fn label(self: Endian) []const u8 {
        return switch (self) {
            .none => "none",
            .@"8in16" => "8in16",
            .@"8in32" => "8in32",
            .@"16in32" => "16in32",
            _ => "unknown",
        };
    }

    /// Apply the swizzle to one dword read out of the surface.
    pub fn apply(self: Endian, value: u32) u32 {
        return switch (self) {
            .none => value,
            .@"8in16" => ((value & 0x00FF00FF) << 8) | ((value & 0xFF00FF00) >> 8),
            .@"8in32" => @byteSwap(value),
            .@"16in32" => (value << 16) | (value >> 16),
            _ => value,
        };
    }
};

/// The front buffer formats `VdSwap` accepts. The emulator asserts the format
/// is one of these before it will encode a swap, so a third value here would be
/// a format no swap can name.
pub const Format = enum(u8) {
    /// Eight bits per channel.
    k_8_8_8_8 = 6,
    /// Ten bits of colour, two of alpha, stored as if it were 16-bit channels.
    k_2_10_10_10_as_16_16_16_16 = 61,
    _,

    pub fn label(self: Format) []const u8 {
        return switch (self) {
            .k_8_8_8_8 => "k_8_8_8_8",
            .k_2_10_10_10_as_16_16_16_16 => "k_2_10_10_10_AS_16_16_16_16",
            _ => "unsupported",
        };
    }

    pub fn supported(self: Format) bool {
        return switch (self) {
            .k_8_8_8_8, .k_2_10_10_10_as_16_16_16_16 => true,
            _ => false,
        };
    }
};

/// Blocks along one edge of a tile. A pitch is rounded up to this, which is why
/// a 1152-wide surface has a 1152-block pitch and a 1153-wide one has 1184.
pub const tile_edge: u32 = 32;

pub fn alignPitch(pitch: u32) u32 {
    return (pitch + (tile_edge - 1)) & ~(tile_edge - 1);
}

/// Byte offset of a block within a tiled 2D surface.
///
/// Transcribed from the emulator's `GetTiledOffset2D`. The bit mixing is not
/// something to re-derive: it was itself reverse-engineered, and a plausible
/// rearrangement produces a picture rather than an error.
pub fn tiledOffset2D(x: u32, y: u32, pitch: u32, bytes_per_block_log2: u5) u32 {
    const aligned_pitch = alignPitch(pitch);
    const xi: i64 = @intCast(x);
    const yi: i64 = @intCast(y);
    const shift: u6 = @intCast(@as(u32, bytes_per_block_log2));

    const macro: i64 = ((xi >> 5) + (yi >> 5) * @as(i64, aligned_pitch >> 5)) << (shift + 7);
    const micro: i64 = ((xi & 7) + ((yi & 0xE) << 2)) << shift;
    const offset: i64 = macro + ((micro & ~@as(i64, 0xF)) << 1) + (micro & 0xF) + ((yi & 1) << 4);
    const mixed: i64 = ((offset & ~@as(i64, 0x1FF)) << 3) + ((yi & 16) << 7) +
        ((offset & 0x1C0) << 2) + (((((yi & 8) >> 2) + (xi >> 3)) & 3) << 6) + (offset & 0x3F);
    return @intCast(mixed);
}

/// Bytes a tiled 32-bit surface of this size occupies. A converter that sizes
/// the source by `width * height * 4` reads past the end of every tiled surface
/// whose width is not a multiple of the tile edge.
pub fn tiledSizeBytes32(width: u32, height: u32) u64 {
    const pitch = alignPitch(width);
    const rows = alignPitch(height);
    return @as(u64, pitch) * rows * 4;
}

pub fn linearSizeBytes32(width: u32, height: u32, row_pitch_bytes: u32) u64 {
    const pitch = if (row_pitch_bytes != 0) row_pitch_bytes else width * 4;
    return @as(u64, pitch) * height;
}

/// Everything needed to read a front buffer, stated rather than assumed.
pub const Surface = struct {
    width: u32,
    height: u32,
    format: Format = .k_8_8_8_8,
    endian: Endian = .@"8in32",
    tiled: bool = true,
    /// Bytes per row for a linear surface. Zero means tightly packed. Ignored
    /// when tiled, where the pitch is derived from the aligned width.
    row_pitch_bytes: u32 = 0,

    pub fn requiredBytes(self: Surface) u64 {
        return if (self.tiled)
            tiledSizeBytes32(self.width, self.height)
        else
            linearSizeBytes32(self.width, self.height, self.row_pitch_bytes);
    }

    /// Whether this describes something a window could show. Extents are
    /// bounded rather than merely non-zero: a converter handed a 30000×2
    /// surface will happily spend a second producing an unviewable image.
    pub fn presentable(self: Surface) bool {
        if (!self.format.supported()) return false;
        if (self.width < 64 or self.height < 64) return false;
        if (self.width > 4096 or self.height > 4096) return false;
        return true;
    }
};

/// Why a conversion could not happen. Each is a different thing to fix; a
/// single `false` sends a reader nowhere.
pub const Failure = enum {
    unsupported_format,
    implausible_extent,
    source_too_small,
    destination_too_small,

    pub fn label(self: Failure) []const u8 {
        return switch (self) {
            .unsupported_format => "the front buffer's pixel format is not one a swap can name, so this is not a front buffer",
            .implausible_extent => "the extent is outside anything a display produced; converting it would spend real time on an unviewable image",
            .source_too_small => "the surface is shorter than its extent, pitch and tiling require, so the tail of the picture is not in memory",
            .destination_too_small => "the destination cannot hold the converted image",
        };
    }
};

/// Convert a console front buffer to tightly packed little-endian BGRA8, which
/// is what the swapchains this runs against want.
///
/// Deliberately a pure function over two slices: the caller owns both, so this
/// can be tested exhaustively and cannot be the thing that faults on unmapped
/// guest memory.
pub fn convertToBgra8(
    source: []const u8,
    surface: Surface,
    destination: []u8,
) ?Failure {
    if (!surface.format.supported()) return .unsupported_format;
    if (!surface.presentable()) return .implausible_extent;
    if (source.len < surface.requiredBytes()) return .source_too_small;
    const needed = @as(u64, surface.width) * surface.height * 4;
    if (destination.len < needed) return .destination_too_small;

    const source_pitch: u32 = if (surface.tiled)
        alignPitch(surface.width)
    else if (surface.row_pitch_bytes != 0)
        surface.row_pitch_bytes / 4
    else
        surface.width;

    var y: u32 = 0;
    while (y < surface.height) : (y += 1) {
        var x: u32 = 0;
        while (x < surface.width) : (x += 1) {
            const byte_offset: usize = if (surface.tiled)
                tiledOffset2D(x, y, surface.width, 2)
            else
                (@as(usize, y) * source_pitch + x) * 4;
            // Guarded per pixel rather than per surface: the tiled offset is a
            // bit-mixing function, and a bound proved for the last pixel is not
            // a bound proved for every pixel.
            if (byte_offset + 4 > source.len) return .source_too_small;
            const raw = std.mem.readInt(u32, source[byte_offset..][0..4], .little);
            const swizzled = surface.endian.apply(raw);
            const pixel = switch (surface.format) {
                .k_2_10_10_10_as_16_16_16_16 => expand2101010(swizzled),
                else => swizzled,
            };
            const at: usize = (@as(usize, y) * surface.width + x) * 4;
            // The console stores ARGB; the destination wants BGRA.
            destination[at + 0] = @truncate(pixel >> 0);
            destination[at + 1] = @truncate(pixel >> 8);
            destination[at + 2] = @truncate(pixel >> 16);
            destination[at + 3] = @truncate(pixel >> 24);
        }
    }
    return null;
}

/// Ten-bit colour to eight, by taking the top bits. Replicating the high bits
/// into the low ones would be marginally more accurate and materially slower,
/// and this runs per pixel per frame.
fn expand2101010(value: u32) u32 {
    const r: u32 = (value >> 20) & 0x3FF;
    const g: u32 = (value >> 10) & 0x3FF;
    const b: u32 = value & 0x3FF;
    const a: u32 = (value >> 30) & 0x3;
    return ((a * 85) << 24) | ((r >> 2) << 16) | ((g >> 2) << 8) | (b >> 2);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "a pitch is rounded up to the tile edge, and an aligned one is unchanged" {
    try std.testing.expectEqual(@as(u32, 32), alignPitch(1));
    try std.testing.expectEqual(@as(u32, 1152), alignPitch(1152));
    try std.testing.expectEqual(@as(u32, 1184), alignPitch(1153));
    try std.testing.expectEqual(@as(u32, 1280), alignPitch(1280));
}

// The property a transcribed bit-mixing function can fail while still looking
// plausible: two pixels landing on one address silently drops half the picture.
test "the tiled address function is injective across a tile" {
    var seen = std.mem.zeroes([32 * 32]bool);
    var y: u32 = 0;
    while (y < 32) : (y += 1) {
        var x: u32 = 0;
        while (x < 32) : (x += 1) {
            const offset = tiledOffset2D(x, y, 32, 2);
            // Byte offsets of 4-byte blocks: unaligned would tear every pixel.
            try std.testing.expectEqual(@as(u32, 0), offset % 4);
            const block = offset / 4;
            try std.testing.expect(block < seen.len);
            try std.testing.expect(!seen[block]);
            seen[block] = true;
        }
    }
    // Every block in the tile is the destination of exactly one pixel, so the
    // mapping is a permutation and no part of the picture is dropped.
    for (seen) |touched| try std.testing.expect(touched);
}

test "no tiled address escapes the surface it belongs to" {
    const width: u32 = 1280;
    const height: u32 = 720;
    const size = tiledSizeBytes32(width, height);
    var y: u32 = 0;
    while (y < height) : (y += 17) {
        var x: u32 = 0;
        while (x < width) : (x += 13) {
            try std.testing.expect(tiledOffset2D(x, y, width, 2) + 4 <= size);
        }
    }
}

// Sizing a tiled surface by width*height*4 reads past the end of every surface
// whose extent is not a multiple of the tile edge — which is most of them.
test "a tiled surface is larger than its extent when the extent is unaligned" {
    try std.testing.expectEqual(@as(u64, 1280 * 736 * 4), tiledSizeBytes32(1280, 720));
    try std.testing.expect(tiledSizeBytes32(1280, 720) > @as(u64, 1280) * 720 * 4);
    // An aligned extent needs no padding.
    try std.testing.expectEqual(@as(u64, 1280 * 704 * 4), tiledSizeBytes32(1280, 704));
}

test "a linear surface round-trips through the converter unchanged" {
    const width: u32 = 64;
    const height: u32 = 64;
    var source = std.mem.zeroes([width * height * 4]u8);
    for (0..width * height) |index| {
        std.mem.writeInt(u32, source[index * 4 ..][0..4], @intCast(0xFF000000 | index), .little);
    }
    var destination = std.mem.zeroes([width * height * 4]u8);
    try std.testing.expect(convertToBgra8(&source, .{
        .width = width,
        .height = height,
        .endian = .none,
        .tiled = false,
    }, &destination) == null);
    try std.testing.expectEqualSlices(u8, &source, &destination);
}

// The wrong swizzle produces a picture, not an error: red and blue exchanged is
// the classic emulator screenshot that looks almost right.
test "each endian swizzle rearranges bytes the way its name says" {
    try std.testing.expectEqual(@as(u32, 0x11223344), Endian.none.apply(0x11223344));
    try std.testing.expectEqual(@as(u32, 0x22114433), Endian.@"8in16".apply(0x11223344));
    try std.testing.expectEqual(@as(u32, 0x44332211), Endian.@"8in32".apply(0x11223344));
    try std.testing.expectEqual(@as(u32, 0x33441122), Endian.@"16in32".apply(0x11223344));
    // Every swizzle is its own inverse, which is what makes a wrong one
    // recoverable rather than lossy.
    inline for (.{ Endian.none, Endian.@"8in16", Endian.@"8in32", Endian.@"16in32" }) |endian| {
        try std.testing.expectEqual(@as(u32, 0x11223344), endian.apply(endian.apply(0x11223344)));
    }
}

test "a tiled surface converts to the linear image it encodes" {
    const width: u32 = 64;
    const height: u32 = 64;
    var source = std.mem.zeroes([@intCast(tiledSizeBytes32(width, height))]u8);
    // Paint each pixel with its own linear index through the tiled address
    // function, so a correct conversion recovers a simple ramp.
    var y: u32 = 0;
    while (y < height) : (y += 1) {
        var x: u32 = 0;
        while (x < width) : (x += 1) {
            const offset = tiledOffset2D(x, y, width, 2);
            std.mem.writeInt(u32, source[offset..][0..4], 0xFF000000 | (y * width + x), .little);
        }
    }

    var destination = std.mem.zeroes([width * height * 4]u8);
    try std.testing.expect(convertToBgra8(&source, .{
        .width = width,
        .height = height,
        .endian = .none,
        .tiled = true,
    }, &destination) == null);

    for (0..width * height) |index| {
        const pixel = std.mem.readInt(u32, destination[index * 4 ..][0..4], .little);
        try std.testing.expectEqual(@as(u32, 0xFF000000 | @as(u32, @intCast(index))), pixel);
    }
}

test "every refusal names a different thing to fix" {
    var destination = std.mem.zeroes([64 * 64 * 4]u8);
    const source = std.mem.zeroes([64 * 64 * 4]u8);

    try std.testing.expectEqual(Failure.unsupported_format, convertToBgra8(&source, .{
        .width = 64,
        .height = 64,
        .format = @enumFromInt(3),
        .tiled = false,
    }, &destination).?);

    try std.testing.expectEqual(Failure.implausible_extent, convertToBgra8(&source, .{
        .width = 8,
        .height = 8,
        .tiled = false,
    }, &destination).?);

    // A tiled 64x64 needs no more than a linear one here, so shorten the source
    // to prove the length check rather than the tiling.
    try std.testing.expectEqual(Failure.source_too_small, convertToBgra8(source[0..1024], .{
        .width = 64,
        .height = 64,
        .tiled = false,
    }, &destination).?);

    try std.testing.expectEqual(Failure.destination_too_small, convertToBgra8(&source, .{
        .width = 64,
        .height = 64,
        .tiled = false,
    }, destination[0..16]).?);

    inline for (.{
        Failure.unsupported_format, Failure.implausible_extent,
        Failure.source_too_small,   Failure.destination_too_small,
    }) |failure| {
        try std.testing.expect(failure.label().len > 0);
    }
}

test "a padded linear row pitch is honoured rather than assumed packed" {
    const width: u32 = 64;
    const height: u32 = 64;
    const pitch: u32 = 96 * 4;
    var source = std.mem.zeroes([pitch * height]u8);
    var y: u32 = 0;
    while (y < height) : (y += 1) {
        std.mem.writeInt(u32, source[y * pitch ..][0..4], 0xFF000000 | y, .little);
    }
    var destination = std.mem.zeroes([width * height * 4]u8);
    try std.testing.expect(convertToBgra8(&source, .{
        .width = width,
        .height = height,
        .endian = .none,
        .tiled = false,
        .row_pitch_bytes = pitch,
    }, &destination) == null);

    var row: u32 = 0;
    while (row < height) : (row += 1) {
        const pixel = std.mem.readInt(u32, destination[row * width * 4 ..][0..4], .little);
        try std.testing.expectEqual(@as(u32, 0xFF000000 | row), pixel);
    }
}

test "ten-bit colour narrows to eight without wrapping a channel" {
    // Full white in 2:10:10:10 stays white rather than overflowing to black.
    const white = expand2101010(0xFFFFFFFF);
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), white);
    try std.testing.expectEqual(@as(u32, 0xFF000000), expand2101010(0xC0000000));
    // The red channel alone lands in the red byte, not in green or blue.
    try std.testing.expectEqual(@as(u32, 0x00FF0000), expand2101010(0x3FF << 20));
}

test "a surface whose extent no display produced is refused before conversion" {
    try std.testing.expect(!(Surface{ .width = 30000, .height = 2 }).presentable());
    try std.testing.expect(!(Surface{ .width = 0, .height = 0 }).presentable());
    try std.testing.expect((Surface{ .width = 1280, .height = 720 }).presentable());
    try std.testing.expect((Surface{ .width = 1152, .height = 640 }).presentable());
}
