//! Xenos to host format conversion.
//!
//! The console stores colour big-endian with a per-surface swizzle on top. A
//! host expects little-endian in a channel order of its own. Getting the
//! combination wrong produces an image with red and blue exchanged — which
//! renders perfectly and is the single most common wrong-looking-but-working
//! emulator screenshot there is.
//!
//! ## Why the two steps are kept separate
//!
//! Endianness and channel order are different transformations that happen to
//! be the same operation for one common format. Folding them into a single
//! byte-swap works for `k_8_8_8_8` and then fails for every 16-bit format,
//! where the swap is within 16-bit units rather than across the dword. Keeping
//! them apart means the 16-bit case is a different swizzle rather than a
//! special case bolted onto a byte swap.

const std = @import("std");
const contract = @import("xenia_texture_contract");
const texture_format_contract = @import("xenia_texture_format_contract");

pub const Error = error{
    UnsupportedConversion,
    BufferTooSmall,
};

/// Runtime-facing bridge to the package's signed packed-10 conversion. The
/// package owns the reviewed bit-level semantics; this library owns the
/// texture-cache-facing entry point so a future Vulkan, Metal, or CPU upload
/// path cannot invent a second interpretation of the same Xenos word.
pub fn unpackSigned2101010(word: u32) [4]i16 {
    return texture_format_contract.unpackSigned2_10_10_10(word);
}

/// Channel order, independent of byte order.
pub const ChannelOrder = enum {
    rgba,
    bgra,
    argb,
    abgr,
};

/// Reorder the channels of an 8-bit-per-channel pixel.
///
/// Takes and returns a dword whose bytes are already in host byte order; the
/// endian swizzle is applied separately, by the texture contract's `Endian`.
pub fn reorderChannels(pixel: u32, from: ChannelOrder, to: ChannelOrder) u32 {
    if (from == to) return pixel;
    const channels = unpack(pixel, from);
    return pack(channels, to);
}

const Channels = struct { r: u8, g: u8, b: u8, a: u8 };

fn unpack(pixel: u32, order: ChannelOrder) Channels {
    const b0: u8 = @truncate(pixel >> 24);
    const b1: u8 = @truncate(pixel >> 16);
    const b2: u8 = @truncate(pixel >> 8);
    const b3: u8 = @truncate(pixel);
    return switch (order) {
        .rgba => .{ .r = b0, .g = b1, .b = b2, .a = b3 },
        .bgra => .{ .b = b0, .g = b1, .r = b2, .a = b3 },
        .argb => .{ .a = b0, .r = b1, .g = b2, .b = b3 },
        .abgr => .{ .a = b0, .b = b1, .g = b2, .r = b3 },
    };
}

fn pack(channels: Channels, order: ChannelOrder) u32 {
    const parts: [4]u8 = switch (order) {
        .rgba => .{ channels.r, channels.g, channels.b, channels.a },
        .bgra => .{ channels.b, channels.g, channels.r, channels.a },
        .argb => .{ channels.a, channels.r, channels.g, channels.b },
        .abgr => .{ channels.a, channels.b, channels.g, channels.r },
    };
    return (@as(u32, parts[0]) << 24) |
        (@as(u32, parts[1]) << 16) |
        (@as(u32, parts[2]) << 8) |
        @as(u32, parts[3]);
}

/// Expand a 5:6:5 pixel to 8:8:8:8.
///
/// Replicating the high bits into the low ones rather than shifting left and
/// leaving zeros: a plain shift makes full white become 0xF8FCF8 instead of
/// 0xFFFFFF, so every bright surface is very slightly grey and gradients band.
pub fn expand565(pixel: u16) u32 {
    const r5: u32 = (pixel >> 11) & 0x1F;
    const g6: u32 = (pixel >> 5) & 0x3F;
    const b5: u32 = pixel & 0x1F;
    const r = (r5 << 3) | (r5 >> 2);
    const g = (g6 << 2) | (g6 >> 4);
    const b = (b5 << 3) | (b5 >> 2);
    return (r << 24) | (g << 16) | (b << 8) | 0xFF;
}

/// Expand a 1:5:5:5 pixel to 8:8:8:8.
pub fn expand1555(pixel: u16) u32 {
    const a1: u32 = (pixel >> 15) & 1;
    const r5: u32 = (pixel >> 10) & 0x1F;
    const g5: u32 = (pixel >> 5) & 0x1F;
    const b5: u32 = pixel & 0x1F;
    const r = (r5 << 3) | (r5 >> 2);
    const g = (g5 << 3) | (g5 >> 2);
    const b = (b5 << 3) | (b5 >> 2);
    const a: u32 = if (a1 == 1) 0xFF else 0x00;
    return (r << 24) | (g << 16) | (b << 8) | a;
}

/// Expand a 4:4:4:4 pixel to 8:8:8:8.
pub fn expand4444(pixel: u16) u32 {
    const a4: u32 = (pixel >> 12) & 0xF;
    const r4: u32 = (pixel >> 8) & 0xF;
    const g4: u32 = (pixel >> 4) & 0xF;
    const b4: u32 = pixel & 0xF;
    return ((r4 << 4 | r4) << 24) |
        ((g4 << 4 | g4) << 16) |
        ((b4 << 4 | b4) << 8) |
        (a4 << 4 | a4);
}

/// Apply the surface swizzle then reorder channels, in that order.
///
/// The order is the contract: the swizzle describes how the GPU reads bytes
/// out of memory, and channel order describes what those bytes mean. Doing them
/// the other way round applies a byte permutation to already-reordered data.
pub fn convertPixel(
    raw: u32,
    endian: contract.Endian,
    from: ChannelOrder,
    to: ChannelOrder,
) u32 {
    return reorderChannels(endian.apply(raw), from, to);
}

/// Convert a whole run of 8888 pixels.
pub fn convertRun(
    source: []const u32,
    destination: []u32,
    endian: contract.Endian,
    from: ChannelOrder,
    to: ChannelOrder,
) Error!void {
    if (destination.len < source.len) return error.BufferTooSmall;
    for (source, 0..) |pixel, index| {
        destination[index] = convertPixel(pixel, endian, from, to);
    }
}

test "identical channel orders are a no-op" {
    try std.testing.expectEqual(@as(u32, 0x11223344), reorderChannels(0x11223344, .rgba, .rgba));
}

test "red and blue exchange is the bug this file exists for" {
    // RGBA 0x11=R 0x22=G 0x33=B 0x44=A becomes BGRA 0x33 0x22 0x11 0x44.
    try std.testing.expectEqual(@as(u32, 0x33221144), reorderChannels(0x11223344, .rgba, .bgra));
    // And back again.
    try std.testing.expectEqual(@as(u32, 0x11223344), reorderChannels(0x33221144, .bgra, .rgba));
}

test "channel reordering round trips through every order" {
    const orders = [_]ChannelOrder{ .rgba, .bgra, .argb, .abgr };
    const original: u32 = 0x11223344;
    for (orders) |from| {
        for (orders) |to| {
            const converted = reorderChannels(original, from, to);
            try std.testing.expectEqual(original, reorderChannels(converted, to, from));
        }
    }
}

test "alpha stays with alpha across orders" {
    // A conversion that moves alpha into a colour channel produces an image
    // that is transparent in patches, which looks like a blending bug.
    const pixel: u32 = 0x1122_3344; // rgba: a = 0x44
    const argb = reorderChannels(pixel, .rgba, .argb);
    try std.testing.expectEqual(@as(u8, 0x44), @as(u8, @truncate(argb >> 24)));
}

test "565 expansion reaches full white" {
    // A plain left shift gives 0xF8FCF8: every bright surface slightly grey,
    // and gradients band. Bit replication is what reaches 0xFF.
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), expand565(0xFFFF));
    try std.testing.expectEqual(@as(u32, 0x000000FF), expand565(0x0000));
    // Pure red: 5 bits all set in the top field.
    try std.testing.expectEqual(@as(u32, 0xFF0000FF), expand565(0xF800));
}

test "1555 alpha is all or nothing" {
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), expand1555(0xFFFF));
    // Same colour, alpha bit clear.
    try std.testing.expectEqual(@as(u32, 0xFFFFFF00), expand1555(0x7FFF));
}

test "4444 expansion replicates each nibble" {
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), expand4444(0xFFFF));
    try std.testing.expectEqual(@as(u32, 0x00000000), expand4444(0x0000));
    // 0x8 becomes 0x88, not 0x80.
    try std.testing.expectEqual(@as(u32, 0x88888888), expand4444(0x8888));
}

test "the swizzle is applied before the channel reorder" {
    // Reversing the order applies a byte permutation to already-reordered
    // data, and the two mistakes do not cancel.
    const raw: u32 = 0x11223344;
    const correct = convertPixel(raw, .@"8in32", .rgba, .bgra);
    // 8in32 byte-swaps to 0x44332211, whose rgba channels are r=0x44 g=0x33
    // b=0x22 a=0x11; repacked as bgra that is 0x22334411.
    try std.testing.expectEqual(@as(u32, 0x22334411), correct);

    // The reverse order would have given a different, wrong answer.
    const reversed = contract.Endian.@"8in32".apply(reorderChannels(raw, .rgba, .bgra));
    try std.testing.expect(reversed != correct);
}

test "a run converts every pixel" {
    const source = [_]u32{ 0x11223344, 0xAABBCCDD };
    var destination: [2]u32 = undefined;
    try convertRun(&source, &destination, .none, .rgba, .bgra);
    try std.testing.expectEqual(@as(u32, 0x33221144), destination[0]);
    try std.testing.expectEqual(@as(u32, 0xCCBBAADD), destination[1]);
}

test "an undersized destination is refused" {
    const source = [_]u32{ 1, 2, 3 };
    var destination: [2]u32 = undefined;
    try std.testing.expectError(
        error.BufferTooSmall,
        convertRun(&source, &destination, .none, .rgba, .bgra),
    );
}

test "a no-op conversion leaves a run untouched" {
    const source = [_]u32{ 0x11223344, 0xAABBCCDD };
    var destination: [2]u32 = undefined;
    try convertRun(&source, &destination, .none, .rgba, .rgba);
    try std.testing.expectEqualSlices(u32, &source, &destination);
}

test "signed packed 10 conversion delegates to the package contract" {
    const word = (@as(u32, 0x1FF) << 0) |
        (@as(u32, 0x200) << 10) |
        (@as(u32, 0x201) << 20) |
        (@as(u32, 0x3) << 30);
    const rgba = unpackSigned2101010(word);
    try std.testing.expectEqual(@as(i16, 32767), rgba[0]);
    try std.testing.expectEqual(@as(i16, -32767), rgba[1]);
    try std.testing.expectEqual(@as(i16, -32767), rgba[2]);
    try std.testing.expectEqual(@as(i16, -32767), rgba[3]);
}
