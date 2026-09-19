//! CPU evidence from the acquired Vulkan image, independent of WSI delivery.
//! RGB thresholds are measurements, NOT a claim that a title rendered correctly.
const std = @import("std");

pub const save_png: u32 = 1;
pub const show_preview: u32 = 2;
pub const diagnostic_exposure: u32 = 4; // +4 EV (x16), independent evidence ONLY
pub const picture_numbering: u32 = 16; // extended native packet; frame remains raw present ID
pub const result_saved: u32 = 1;
pub const result_previewed: u32 = 2;
pub const result_failed: u32 = 4;
pub const max_bytes: u64 = 64 * 1024 * 1024;
pub const max_saved_frames: u64 = 24;

// Matched by RosetteMachOReadbackFrame in native_window_bridge.h. Native ABI,
// not a guest Windows structure; no guest pointers cross this boundary.
pub const Frame = extern struct {
    pixels: [*]const u8,
    length: u64,
    frame: u64,
    swapchain: u64,
    image: u64,
    hash: u64,
    width: u32,
    height: u32,
    format: u32,
    flags: u32,
    visible_pixels: u64,
    bright_pixels: u64,
    transparent_pixels: u64,
    rgb_sum: [3]u64,
    rgb_different_pixels: u64,
    min_rgb: [3]u8,
    max_rgb: [3]u8,
    reserved: [2]u8 = .{ 0, 0 },
    /// Read only when picture_numbering is set. Older 128-byte packets and
    /// offline replay do not carry a native-completed picture epoch.
    content_frame: u64 = 0,
};

pub const Stats = struct {
    hash: u64 = 14_695_981_039_346_656_037,
    first_pixel: u32 = 0,
    any_nonzero: bool = false,
    uniform: bool = true,
    pixel_count: u64 = 0,
    visible_pixels: u64 = 0, // max(R,G,B) > 16
    bright_pixels: u64 = 0, // max(R,G,B) > 64
    transparent_pixels: u64 = 0, // alpha < 255
    rgb_different_pixels: u64 = 0, // RGB differs from the first pixel
    rgb_sum: [3]u64 = .{ 0, 0, 0 },
    min_rgb: [3]u8 = .{ 255, 255, 255 },
    max_rgb: [3]u8 = .{ 0, 0, 0 },

    pub fn mean(self: Stats, channel: usize) u64 {
        return if (self.pixel_count == 0) 0 else self.rgb_sum[channel] / self.pixel_count;
    }

    /// The brightest channel value anywhere in the image, on the 8-bit scale.
    pub fn peak(self: Stats) u8 {
        return @max(self.max_rgb[0], self.max_rgb[1], self.max_rgb[2]);
    }

    /// No arbitrary brightness cutoff: even 1/255 RGB variation is detail.
    /// This is image evidence, not recognition of a game or screen scanout.
    pub fn hasRgbDetail(self: Stats) bool {
        return self.pixel_count != 0 and self.rgb_different_pixels != 0 and self.peak() != 0;
    }
};

/// How a four-byte pixel is laid out. Every format the probe reads back is
/// four bytes per pixel; what differs is where each channel sits and how wide
/// it is. Ten-bit channels are reduced to their top eight bits for the
/// statistics so a 10-bit intermediate and the 8-bit swapchain it feeds are
/// measured on one scale.
pub const Layout = enum {
    rgba8,
    bgra8,
    /// VK_FORMAT_A2B10G10R10_UNORM_PACK32: R in bits 0-9, G 10-19, B 20-29,
    /// A 30-31. Xenia's guest output image and its 10-bit front buffer.
    a2b10g10r10,
};

pub fn layoutFor(format: u32) ?Layout {
    return switch (format) {
        37, 43 => .rgba8, // VK_FORMAT_R8G8B8A8_UNORM / SRGB
        51 => .rgba8, // VK_FORMAT_A8B8G8R8_UNORM_PACK32: little-endian bytes are R,G,B,A
        44, 50 => .bgra8, // VK_FORMAT_B8G8R8A8_UNORM / SRGB
        64 => .a2b10g10r10, // VK_FORMAT_A2B10G10R10_UNORM_PACK32
        else => null,
    };
}

/// Kept for the Cocoa preview, which only understands 8-bit channel orders;
/// a ten-bit image reads as neither and must not be handed to it.
pub fn isBgra(format: u32) ?bool {
    return switch (layoutFor(format) orelse return null) {
        .rgba8 => false,
        .bgra8 => true,
        .a2b10g10r10 => null,
    };
}

pub fn byteLength(width: u32, height: u32, format: u32) ?u64 {
    _ = layoutFor(format) orelse return null;
    if (width == 0 or height == 0) return null;
    if (@as(u64, width) > max_bytes / 4 / height) return null;
    const length = @as(u64, width) * height * 4;
    return if (length <= max_bytes) length else null;
}

pub fn analyze(bytes: []const u8, width: u32, height: u32, format: u32) !Stats {
    const length = byteLength(width, height, format) orelse return error.InvalidFrame;
    if (bytes.len != length) return error.InvalidLength;
    const layout = layoutFor(format).?;
    var stats = Stats{ .pixel_count = length / 4, .first_pixel = std.mem.readInt(u32, bytes[0..4], .little) };
    const first_rgb = rgb(bytes[0..4], layout);
    var offset: usize = 0;
    while (offset < bytes.len) : (offset += 4) {
        const pixel = bytes[offset..][0..4];
        for (pixel) |byte| {
            stats.any_nonzero = stats.any_nonzero or byte != 0;
            stats.hash ^= byte;
            stats.hash *%= 1_099_511_628_211;
        }
        stats.uniform = stats.uniform and std.mem.readInt(u32, pixel, .little) == stats.first_pixel;
        const channels = rgb(pixel, layout);
        if (!std.mem.eql(u8, &channels, &first_rgb)) stats.rgb_different_pixels += 1;
        const peak = @max(channels[0], channels[1], channels[2]);
        if (peak > 16) stats.visible_pixels += 1;
        if (peak > 64) stats.bright_pixels += 1;
        if (alpha(pixel, layout) < 255) stats.transparent_pixels += 1;
        for (channels, 0..) |value, channel| {
            stats.rgb_sum[channel] += value;
            stats.min_rgb[channel] = @min(stats.min_rgb[channel], value);
            stats.max_rgb[channel] = @max(stats.max_rgb[channel], value);
        }
    }
    return stats;
}

/// Xenos 7e3 floating point (3-bit exponent, 7-bit mantissa, no sign) in the
/// low ten bits, as `xe::gpu::xenos::Float7e3To32` decodes it, in thousandths:
/// 0x180 (1.0) is 1000 and the largest pattern 0x3FF is 31875. A 10-bit front
/// buffer that holds these patterns reads dim when measured as UNORM (1.0 is
/// 384/1023), so a swap texture's brightness has to be read both ways.
pub fn sevenE3ToMilli(f10: u32) u32 {
    const pattern = f10 & 0x3FF;
    if (pattern == 0) return 0;
    var mantissa: u32 = pattern & 0x7F;
    var exponent: i32 = @intCast(pattern >> 7);
    if (exponent == 0) {
        const leading: i32 = @as(i32, @clz(mantissa)) - (32 - 8);
        exponent = 1 - leading;
        mantissa = (mantissa << @intCast(leading)) & 0x7F;
    }
    const value = (1.0 + @as(f64, @floatFromInt(mantissa)) / 128.0) * std.math.pow(f64, 2.0, @as(f64, @floatFromInt(exponent - 3)));
    return @intFromFloat(@round(value * 1000.0));
}

/// Per-channel 7e3 readings of an `A2B10G10R10` image, in thousandths.
pub const SevenE3Stats = struct {
    pixel_count: u64 = 0,
    max_milli: [3]u32 = .{ 0, 0, 0 },
    sum_milli: [3]u64 = .{ 0, 0, 0 },
    /// Pixels whose brightest channel decodes above 1.0.
    over_one_pixels: u64 = 0,

    pub fn mean(self: SevenE3Stats, channel: usize) u64 {
        return if (self.pixel_count == 0) 0 else self.sum_milli[channel] / self.pixel_count;
    }

    pub fn peak(self: SevenE3Stats) u32 {
        return @max(self.max_milli[0], self.max_milli[1], self.max_milli[2]);
    }
};

/// Read a packed 10-bit image as 7e3 float. Only format 64 holds patterns
/// this decoding applies to; anything else returns null.
pub fn analyzeSevenE3(bytes: []const u8, width: u32, height: u32, format: u32) ?SevenE3Stats {
    if (layoutFor(format) != .a2b10g10r10) return null;
    const length = byteLength(width, height, format) orelse return null;
    if (bytes.len != length) return null;
    var stats = SevenE3Stats{ .pixel_count = length / 4 };
    var offset: usize = 0;
    while (offset < bytes.len) : (offset += 4) {
        const packed_word = std.mem.readInt(u32, bytes[offset..][0..4], .little);
        var brightest: u32 = 0;
        inline for (0..3) |channel| {
            const milli = sevenE3ToMilli(packed_word >> (channel * 10));
            stats.sum_milli[channel] += milli;
            stats.max_milli[channel] = @max(stats.max_milli[channel], milli);
            brightest = @max(brightest, milli);
        }
        if (brightest > 1000) stats.over_one_pixels += 1;
    }
    return stats;
}

test "7e3 patterns decode as Xenia decodes them" {
    try std.testing.expectEqual(@as(u32, 0), sevenE3ToMilli(0));
    try std.testing.expectEqual(@as(u32, 1000), sevenE3ToMilli(0x180));
    try std.testing.expectEqual(@as(u32, 500), sevenE3ToMilli(0x100));
    try std.testing.expectEqual(@as(u32, 2000), sevenE3ToMilli(0x200));
    try std.testing.expectEqual(@as(u32, 31875), sevenE3ToMilli(0x3FF));
    // Denormals: 0x40 is the largest, 0.5 * 2^-2.
    try std.testing.expectEqual(@as(u32, 125), sevenE3ToMilli(0x40));
    try std.testing.expectEqual(@as(u32, 2), sevenE3ToMilli(0x01));
    // A 10-bit UNORM reading of 0x180 is 96/255, dim; as 7e3 it is white.
    var pixels: [8]u8 = undefined;
    std.mem.writeInt(u32, pixels[0..4], 0x180 | (0x180 << 10) | (0x180 << 20) | (3 << 30), .little);
    std.mem.writeInt(u32, pixels[4..8], 0x200 | (3 << 30), .little);
    const stats = analyzeSevenE3(&pixels, 2, 1, 64).?;
    try std.testing.expectEqual(@as(u32, 2000), stats.max_milli[0]);
    try std.testing.expectEqual(@as(u32, 1000), stats.max_milli[1]);
    try std.testing.expectEqual(@as(u64, 1500), stats.mean(0));
    try std.testing.expectEqual(@as(u64, 1), stats.over_one_pixels);
    try std.testing.expect(analyzeSevenE3(&pixels, 2, 1, 44) == null);
}

fn rgb(pixel: *const [4]u8, layout: Layout) [3]u8 {
    return switch (layout) {
        .bgra8 => .{ pixel[2], pixel[1], pixel[0] },
        .rgba8 => .{ pixel[0], pixel[1], pixel[2] },
        .a2b10g10r10 => blk: {
            const packed_word = std.mem.readInt(u32, pixel, .little);
            break :blk .{
                @intCast((packed_word & 1023) >> 2),
                @intCast(((packed_word >> 10) & 1023) >> 2),
                @intCast(((packed_word >> 20) & 1023) >> 2),
            };
        },
    };
}

fn alpha(pixel: *const [4]u8, layout: Layout) u8 {
    return switch (layout) {
        .bgra8, .rgba8 => pixel[3],
        // Two bits: 0, 1, 2, 3 -> 0, 85, 170, 255.
        .a2b10g10r10 => @intCast((std.mem.readInt(u32, pixel, .little) >> 30) * 85),
    };
}

/// Opaque display conversion deliberately ignores source alpha. The raw PNG
/// keeps it; a separate RGB PNG/preview makes alpha-only loss observable.
pub fn opaqueRgba(source: []const u8, destination: []u8, format: u32) !void {
    const layout = layoutFor(format) orelse return error.InvalidFrame;
    if (source.len == 0 or source.len % 4 != 0 or destination.len != source.len) return error.InvalidLength;
    var offset: usize = 0;
    while (offset < source.len) : (offset += 4) {
        const channels = rgb(source[offset..][0..4], layout);
        destination[offset..][0..4].* = .{ channels[0], channels[1], channels[2], 255 };
    }
}

pub const Policy = struct {
    content_samples: u64 = 0,
    saved_frames: u64 = 0,
    startup_saved: u64 = 0,
    waiting_saved: u64 = 0,
    picture_saved: u64 = 0,
    last_saved_picture: u64 = 0,

    fn wantsSave(self: Policy, raw_present: u64, content: bool, picture_frame: u64) bool {
        if (self.saved_frames >= max_saved_frames) return false;
        if (!content) return raw_present <= 4 and self.startup_saved < 4;
        if (picture_frame == 0) return self.waiting_saved < 4;
        // Reserve sixteen of the 24 PNG attempts for the actual picture.
        return self.picture_saved < 16 and (self.picture_saved < 8 or picture_frame -| self.last_saved_picture >= 60);
    }

    pub fn wantsCapture(self: Policy, raw_present: u64, content: bool, picture_frame: u64, preview: bool) bool {
        return preview or self.wantsSave(raw_present, content, picture_frame);
    }

    pub fn flags(self: *Policy, raw_present: u64, content: bool, picture_frame: u64, preview: bool) u32 {
        const save = self.wantsSave(raw_present, content, picture_frame);
        if (content) self.content_samples +|= 1;
        // Count attempts, not successes: a full disk must not create unbounded retries.
        if (save) {
            self.saved_frames += 1;
            if (!content) self.startup_saved += 1 else if (picture_frame == 0) self.waiting_saved += 1 else {
                self.picture_saved += 1;
                self.last_saved_picture = picture_frame;
            }
        }
        return (if (save) save_png else @as(u32, 0)) | (if (preview) show_preview else @as(u32, 0));
    }
};

test "readback native packet layout matches Cocoa" {
    try std.testing.expectEqual(@as(usize, 136), @sizeOf(Frame));
    try std.testing.expectEqual(@as(usize, 48), @offsetOf(Frame, "width"));
    try std.testing.expectEqual(@as(usize, 120), @offsetOf(Frame, "min_rgb"));
    try std.testing.expectEqual(@as(usize, 128), @offsetOf(Frame, "content_frame"));
}

test "opaque black and near-black variation do not prove visible detail" {
    const black = try analyze(&.{ 0, 0, 0, 255, 0, 0, 0, 255 }, 2, 1, 44);
    try std.testing.expect(black.any_nonzero and black.uniform);
    try std.testing.expectEqual(@as(u64, 0), black.visible_pixels);
    const noise = try analyze(&.{ 6, 0, 5, 255, 5, 0, 5, 255 }, 2, 1, 44);
    try std.testing.expect(!noise.uniform);
    try std.testing.expectEqual(@as(u64, 1), noise.rgb_different_pixels);
    try std.testing.expectEqual(@as(u64, 0), noise.visible_pixels);
    try std.testing.expectEqual(@as(u64, 5), noise.mean(0));
    try std.testing.expectEqual(@as(u8, 6), noise.peak());
}

test "alpha-only variation is not RGB variation and transparent content survives preview" {
    const alpha_only = try analyze(&.{ 0, 0, 0, 0, 0, 0, 0, 255 }, 2, 1, 37);
    try std.testing.expect(!alpha_only.uniform);
    try std.testing.expectEqual(@as(u64, 0), alpha_only.rgb_different_pixels);
    const source = [_]u8{ 0, 10, 200, 0, 255, 30, 0, 128 };
    const stats = try analyze(&source, 2, 1, 50);
    try std.testing.expectEqual(@as(u64, 2), stats.transparent_pixels);
    try std.testing.expectEqual(@as(u64, 2), stats.bright_pixels);
    var destination: [8]u8 = undefined;
    try opaqueRgba(&source, &destination, 50);
    try std.testing.expectEqualSlices(u8, &.{ 200, 10, 0, 255, 0, 30, 255, 255 }, &destination);
}

test "RGBA and BGRA UNORM and SRGB preserve channel order" {
    for ([_]u32{ 37, 43, 44, 50, 51 }) |format| {
        const bytes = if (isBgra(format).?) [_]u8{ 3, 17, 201, 255 } else [_]u8{ 201, 17, 3, 255 };
        const stats = try analyze(&bytes, 1, 1, format);
        try std.testing.expectEqual([3]u8{ 201, 17, 3 }, stats.min_rgb);
        try std.testing.expectEqual([3]u8{ 201, 17, 3 }, stats.max_rgb);
    }
}

test "ten-bit packed pixels are measured on the eight-bit scale" {
    // R = 1023 (white), G = 5 (dark), B = 64 (16/255), A = 3 (opaque).
    const packed_word: u32 = 1023 | (5 << 10) | (64 << 20) | (3 << 30);
    var bytes: [8]u8 = undefined;
    std.mem.writeInt(u32, bytes[0..4], packed_word, .little);
    std.mem.writeInt(u32, bytes[4..8], packed_word & ~(@as(u32, 3) << 30), .little);
    const stats = try analyze(&bytes, 2, 1, 64);
    try std.testing.expectEqual([3]u8{ 255, 1, 16 }, stats.max_rgb);
    try std.testing.expectEqual(@as(u64, 2), stats.visible_pixels);
    try std.testing.expectEqual(@as(u64, 2), stats.bright_pixels);
    // The second pixel's two alpha bits are zero, so it reads transparent.
    try std.testing.expectEqual(@as(u64, 1), stats.transparent_pixels);
    // The preview cannot take this layout; the probe must not hand it over.
    try std.testing.expect(isBgra(64) == null);
    try std.testing.expect(layoutFor(64) == .a2b10g10r10);
}

test "malformed and excessive frame sizes are refused before memory access" {
    try std.testing.expect(byteLength(0, 1, 44) == null);
    try std.testing.expect(byteLength(std.math.maxInt(u32), std.math.maxInt(u32), 44) == null);
    try std.testing.expect(byteLength(1280, 720, 999) == null);
    try std.testing.expectError(error.InvalidLength, analyze(&.{ 1, 2, 3 }, 1, 1, 44));
    try std.testing.expectError(error.InvalidLength, opaqueRgba(&.{ 1, 2, 3, 4 }, &.{}, 44));
}

test "first content frames are captured even after an early nonuniform sample" {
    var policy = Policy{};
    for (1..200001) |frame| _ = policy.flags(frame, false, 0, false);
    try std.testing.expectEqual(@as(u64, 4), policy.saved_frames);
    for (1..5001) |frame| _ = policy.flags(200000 + frame, true, 0, false);
    try std.testing.expectEqual(@as(u64, 8), policy.saved_frames);
    for (1..9) |frame| {
        try std.testing.expect(policy.wantsCapture(205000 + frame, true, frame, false));
        try std.testing.expect(policy.flags(205000 + frame, true, frame, false) & save_png != 0);
    }
    try std.testing.expect(!policy.wantsCapture(205009, true, 9, false));
    try std.testing.expect(policy.wantsCapture(205009, true, 9, true));
    for (1..9) |sample| _ = policy.flags(205008 + sample * 60, true, 8 + sample * 60, false);
    try std.testing.expectEqual(max_saved_frames, policy.saved_frames);
    try std.testing.expectEqual(show_preview, policy.flags(206000, true, 1000, true));
}

test "picture admission sees dim RGB but not alpha-only or opaque black pixels" {
    try std.testing.expect((try analyze(&.{ 0, 0, 0, 255, 1, 0, 0, 255 }, 2, 1, 37)).hasRgbDetail());
    try std.testing.expect(!(try analyze(&.{ 0, 0, 0, 0, 0, 0, 0, 255 }, 2, 1, 37)).hasRgbDetail());
    try std.testing.expect(!(try analyze(&.{ 255, 255, 255, 255, 255, 255, 255, 255 }, 2, 1, 37)).hasRgbDetail());
}
