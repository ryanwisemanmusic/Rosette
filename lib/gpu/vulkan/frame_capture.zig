//! CPU evidence from the acquired Vulkan image, independent of WSI delivery.
//! RGB thresholds are measurements, NOT a claim that a title rendered correctly.
const std = @import("std");

pub const save_png: u32 = 1;
pub const show_preview: u32 = 2;
pub const diagnostic_exposure: u32 = 4; // +4 EV (x16), independent evidence ONLY
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
};

pub fn isBgra(format: u32) ?bool {
    return switch (format) {
        37, 43 => false, // VK_FORMAT_R8G8B8A8_UNORM / SRGB
        44, 50 => true, // VK_FORMAT_B8G8R8A8_UNORM / SRGB
        else => null,
    };
}

pub fn byteLength(width: u32, height: u32, format: u32) ?u64 {
    _ = isBgra(format) orelse return null;
    if (width == 0 or height == 0) return null;
    if (@as(u64, width) > max_bytes / 4 / height) return null;
    const length = @as(u64, width) * height * 4;
    return if (length <= max_bytes) length else null;
}

pub fn analyze(bytes: []const u8, width: u32, height: u32, format: u32) !Stats {
    const length = byteLength(width, height, format) orelse return error.InvalidFrame;
    if (bytes.len != length) return error.InvalidLength;
    const bgra = isBgra(format).?;
    var stats = Stats{ .pixel_count = length / 4, .first_pixel = std.mem.readInt(u32, bytes[0..4], .little) };
    const first_rgb = rgb(bytes[0..4], bgra);
    var offset: usize = 0;
    while (offset < bytes.len) : (offset += 4) {
        const pixel = bytes[offset..][0..4];
        for (pixel) |byte| {
            stats.any_nonzero = stats.any_nonzero or byte != 0;
            stats.hash ^= byte;
            stats.hash *%= 1_099_511_628_211;
        }
        stats.uniform = stats.uniform and std.mem.readInt(u32, pixel, .little) == stats.first_pixel;
        const channels = rgb(pixel, bgra);
        if (!std.mem.eql(u8, &channels, &first_rgb)) stats.rgb_different_pixels += 1;
        const peak = @max(channels[0], channels[1], channels[2]);
        if (peak > 16) stats.visible_pixels += 1;
        if (peak > 64) stats.bright_pixels += 1;
        if (pixel[3] < 255) stats.transparent_pixels += 1;
        for (channels, 0..) |value, channel| {
            stats.rgb_sum[channel] += value;
            stats.min_rgb[channel] = @min(stats.min_rgb[channel], value);
            stats.max_rgb[channel] = @max(stats.max_rgb[channel], value);
        }
    }
    return stats;
}

fn rgb(pixel: *const [4]u8, bgra: bool) [3]u8 {
    return if (bgra) .{ pixel[2], pixel[1], pixel[0] } else .{ pixel[0], pixel[1], pixel[2] };
}

/// Opaque display conversion deliberately ignores source alpha. The raw PNG
/// keeps it; a separate RGB PNG/preview makes alpha-only loss observable.
pub fn opaqueRgba(source: []const u8, destination: []u8, format: u32) !void {
    const bgra = isBgra(format) orelse return error.InvalidFrame;
    if (source.len == 0 or source.len % 4 != 0 or destination.len != source.len) return error.InvalidLength;
    var offset: usize = 0;
    while (offset < source.len) : (offset += 4) {
        const channels = rgb(source[offset..][0..4], bgra);
        destination[offset..][0..4].* = .{ channels[0], channels[1], channels[2], 255 };
    }
}

pub const Policy = struct {
    content_samples: u64 = 0,
    saved_frames: u64 = 0,

    pub fn needsProbe(self: Policy, frame: u64, content: bool, preview: bool) bool {
        return preview or frame <= 4 or frame % 60 == 0 or (content and self.content_samples < 8);
    }

    pub fn flags(self: *Policy, frame: u64, content: bool, preview: bool) u32 {
        const save = self.saved_frames < max_saved_frames and
            (frame <= 4 or frame % 60 == 0 or (content and self.content_samples < 8));
        if (content) self.content_samples +|= 1;
        // Count attempts, not successes: a full disk must not create unbounded retries.
        if (save) self.saved_frames += 1;
        return (if (save) save_png else @as(u32, 0)) | (if (preview) show_preview else @as(u32, 0));
    }
};

test "readback native packet layout matches Cocoa" {
    try std.testing.expectEqual(@as(usize, 128), @sizeOf(Frame));
    try std.testing.expectEqual(@as(usize, 48), @offsetOf(Frame, "width"));
    try std.testing.expectEqual(@as(usize, 120), @offsetOf(Frame, "min_rgb"));
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
}

test "alpha-only variation is not RGB variation and transparent content survives preview" {
    const alpha = try analyze(&.{ 0, 0, 0, 0, 0, 0, 0, 255 }, 2, 1, 37);
    try std.testing.expect(!alpha.uniform);
    try std.testing.expectEqual(@as(u64, 0), alpha.rgb_different_pixels);
    const source = [_]u8{ 0, 10, 200, 0, 255, 30, 0, 128 };
    const stats = try analyze(&source, 2, 1, 50);
    try std.testing.expectEqual(@as(u64, 2), stats.transparent_pixels);
    try std.testing.expectEqual(@as(u64, 2), stats.bright_pixels);
    var destination: [8]u8 = undefined;
    try opaqueRgba(&source, &destination, 50);
    try std.testing.expectEqualSlices(u8, &.{ 200, 10, 0, 255, 0, 30, 255, 255 }, &destination);
}

test "RGBA and BGRA UNORM and SRGB preserve channel order" {
    for ([_]u32{ 37, 43, 44, 50 }) |format| {
        const bytes = if (isBgra(format).?) [_]u8{ 3, 17, 201, 255 } else [_]u8{ 201, 17, 3, 255 };
        const stats = try analyze(&bytes, 1, 1, format);
        try std.testing.expectEqual([3]u8{ 201, 17, 3 }, stats.min_rgb);
        try std.testing.expectEqual([3]u8{ 201, 17, 3 }, stats.max_rgb);
    }
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
    for (1..5) |frame| _ = policy.flags(frame, false, false);
    for (5..13) |frame| {
        try std.testing.expect(policy.needsProbe(frame, true, false));
        try std.testing.expect(policy.flags(frame, true, false) & save_png != 0);
    }
    try std.testing.expect(!policy.needsProbe(13, true, false));
    try std.testing.expect(policy.needsProbe(13, true, true));
    while (policy.saved_frames < max_saved_frames) _ = policy.flags(60, true, false);
    try std.testing.expectEqual(show_preview, policy.flags(60, true, true));
}
