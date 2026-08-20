//! Xbox 360 Xenos EDRAM model and resolve helpers.
//!
//! EDRAM is not a normal linear image.  It is 2048 tiles of 80×16 32-bit
//! samples (10 MiB total), with multisample surfaces changing the sample-space
//! width and height.  The model is intentionally backend-neutral: the Vulkan
//! path can use it for resolve bookkeeping while the CPU frame path can use the
//! same address calculation for diagnostics and readback.

const std = @import("std");

pub const tile_width_samples: u32 = 80;
pub const tile_height_samples: u32 = 16;
pub const tile_count: u32 = 2048;
pub const tile_bytes: u32 = tile_width_samples * tile_height_samples * 4;
pub const size_bytes: usize = tile_count * tile_bytes;

pub const Msaa = enum(u2) {
    x1 = 0,
    x2 = 1,
    x4 = 2,
    _,

    pub fn sampleCount(self: Msaa) u32 {
        return switch (self) {
            .x1 => 1,
            .x2 => 2,
            .x4 => 4,
            _ => 1,
        };
    }
};

pub const Format = enum(u8) {
    color32 = 0,
    color64 = 1,
    depth24s8 = 2,
    depth24fs8 = 3,
};

pub const Surface = struct {
    base_tile: u32 = 0,
    pitch_pixels: u32 = 0,
    width: u32 = 0,
    height: u32 = 0,
    msaa: Msaa = .x1,
    format: Format = .color32,

    pub fn is64Bit(self: Surface) bool {
        return self.format == .color64;
    }

    pub fn bytesPerSample(self: Surface) u32 {
        return if (self.is64Bit()) 8 else 4;
    }

    pub fn sampleExtent(self: Surface) struct { width: u32, height: u32 } {
        return switch (self.msaa) {
            .x1 => .{ .width = self.width, .height = self.height },
            .x2 => .{ .width = self.width, .height = scale(self.height, 2) },
            .x4 => .{ .width = scale(self.width, 2), .height = scale(self.height, 2) },
            _ => .{ .width = self.width, .height = self.height },
        };
    }

    pub fn tilePitch(self: Surface) u32 {
        const samples = self.sampleExtent();
        // RB_SURFACE_INFO.surface_pitch is the logical width in pixels.  The
        // Xenos expands that pitch only for 4x MSAA, then rounds it to the
        // 80-sample tile width.  The max with the requested extent keeps a
        // malformed/narrow pitch from aliasing two visible rows onto one.
        const pitch_samples = if (self.msaa == .x4) scale(self.pitch_pixels, 2) else self.pitch_pixels;
        const width = @max(samples.width, pitch_samples);
        const base = ceilDiv(width, tile_width_samples);
        return if (self.is64Bit()) scale(base, 2) else base;
    }

    pub fn tileCount(self: Surface) u32 {
        const samples = self.sampleExtent();
        const rows = ceilDiv(samples.height, tile_height_samples);
        const product = @as(u64, self.tilePitch()) * rows;
        return if (product > std.math.maxInt(u32)) std.math.maxInt(u32) else @intCast(product);
    }
};

pub const Error = error{
    InvalidSurface,
    OutOfRange,
    BufferTooSmall,
    UnsupportedFormat,
};

pub const Store = struct {
    bytes: []u8,

    pub fn init(bytes: []u8) Store {
        return .{ .bytes = bytes };
    }

    pub fn clear(self: Store, value: u8) void {
        @memset(self.bytes, value);
    }

    pub fn validate(self: Store, surface: Surface) Error!void {
        if (surface.width == 0 or surface.height == 0 or surface.pitch_pixels == 0) return error.InvalidSurface;
        if (@as(u64, surface.base_tile) + surface.tileCount() > tile_count) return error.OutOfRange;
        if (self.bytes.len < size_bytes) return error.BufferTooSmall;
    }

    pub fn pixelOffset(self: Store, surface: Surface, x: u32, y: u32, sample: u32) Error!usize {
        try self.validate(surface);
        if (x >= surface.width or y >= surface.height or sample >= surface.msaa.sampleCount()) return error.OutOfRange;
        const sample_xy = sampleCoordinates(surface.msaa, x, y, sample);
        const pitch_tiles = surface.tilePitch();
        const tile_x = @as(u64, sample_xy.x / tile_width_samples);
        const tile_y = @as(u64, sample_xy.y / tile_height_samples);
        const local_x = sample_xy.x % tile_width_samples;
        const local_y = sample_xy.y % tile_height_samples;
        const bytes_per_sample = surface.bytesPerSample();
        const tiles_per_x: u64 = if (surface.is64Bit()) 2 else 1;
        const tile = @as(u64, surface.base_tile) + tile_y * pitch_tiles + tile_x * tiles_per_x;
        const sample_in_tile = @as(u64, local_y) * tile_width_samples + local_x;
        const offset = tile * tile_bytes + sample_in_tile * bytes_per_sample;
        if (offset > self.bytes.len or bytes_per_sample > self.bytes.len - offset) return error.OutOfRange;
        return @intCast(offset);
    }

    pub fn writeColor(self: Store, surface: Surface, x: u32, y: u32, sample: u32, value: u32) Error!void {
        if (surface.format != .color32) return error.UnsupportedFormat;
        const offset = try self.pixelOffset(surface, x, y, sample);
        std.mem.writeInt(u32, self.bytes[offset..][0..4], value, .little);
    }

    pub fn readColor(self: Store, surface: Surface, x: u32, y: u32, sample: u32) Error!u32 {
        if (surface.format != .color32) return error.UnsupportedFormat;
        const offset = try self.pixelOffset(surface, x, y, sample);
        return std.mem.readInt(u32, self.bytes[offset..][0..4], .little);
    }

    pub fn writeColor64(self: Store, surface: Surface, x: u32, y: u32, sample: u32, value: u64) Error!void {
        if (surface.format != .color64) return error.UnsupportedFormat;
        const offset = try self.pixelOffset(surface, x, y, sample);
        std.mem.writeInt(u64, self.bytes[offset..][0..8], value, .little);
    }

    pub fn readColor64(self: Store, surface: Surface, x: u32, y: u32, sample: u32) Error!u64 {
        if (surface.format != .color64) return error.UnsupportedFormat;
        const offset = try self.pixelOffset(surface, x, y, sample);
        return std.mem.readInt(u64, self.bytes[offset..][0..8], .little);
    }

    /// Depth/stencil surfaces are retained as their native 32-bit packed
    /// value. Xenos uses the low 24 bits for depth and the high byte for
    /// stencil in this backend-neutral store; Vulkan conversion owns any
    /// normalized-depth interpretation.
    pub fn writeDepthStencil(self: Store, surface: Surface, x: u32, y: u32, sample: u32, value: u32) Error!void {
        if (surface.format != .depth24s8 and surface.format != .depth24fs8) return error.UnsupportedFormat;
        const offset = try self.pixelOffset(surface, x, y, sample);
        std.mem.writeInt(u32, self.bytes[offset..][0..4], value, .little);
    }

    pub fn readDepthStencil(self: Store, surface: Surface, x: u32, y: u32, sample: u32) Error!u32 {
        if (surface.format != .depth24s8 and surface.format != .depth24fs8) return error.UnsupportedFormat;
        const offset = try self.pixelOffset(surface, x, y, sample);
        return std.mem.readInt(u32, self.bytes[offset..][0..4], .little);
    }

    pub fn clearColor(self: Store, surface: Surface, value: u32) Error!void {
        if (surface.format != .color32) return error.UnsupportedFormat;
        try self.validate(surface);
        var y: u32 = 0;
        while (y < surface.height) : (y += 1) {
            var x: u32 = 0;
            while (x < surface.width) : (x += 1) {
                var sample: u32 = 0;
                while (sample < surface.msaa.sampleCount()) : (sample += 1) try self.writeColor(surface, x, y, sample, value);
            }
        }
    }

    pub fn clearColor64(self: Store, surface: Surface, value: u64) Error!void {
        if (surface.format != .color64) return error.UnsupportedFormat;
        try self.validate(surface);
        var y: u32 = 0;
        while (y < surface.height) : (y += 1) {
            var x: u32 = 0;
            while (x < surface.width) : (x += 1) {
                var sample: u32 = 0;
                while (sample < surface.msaa.sampleCount()) : (sample += 1) try self.writeColor64(surface, x, y, sample, value);
            }
        }
    }

    pub fn clearDepthStencil(self: Store, surface: Surface, value: u32) Error!void {
        if (surface.format != .depth24s8 and surface.format != .depth24fs8) return error.UnsupportedFormat;
        try self.validate(surface);
        var y: u32 = 0;
        while (y < surface.height) : (y += 1) {
            var x: u32 = 0;
            while (x < surface.width) : (x += 1) {
                var sample: u32 = 0;
                while (sample < surface.msaa.sampleCount()) : (sample += 1) try self.writeDepthStencil(surface, x, y, sample, value);
            }
        }
    }

    /// Resolve a color surface into a tightly-packed RGBA8 image. Samples are
    /// averaged in byte space here; the Vulkan path may replace this with a
    /// hardware resolve, but the reference result remains deterministic.
    pub fn resolveColor(self: Store, surface: Surface, destination: []u8, destination_pitch: u32) Error!void {
        if (surface.format != .color32 and surface.format != .color64) return error.UnsupportedFormat;
        try self.validate(surface);
        const needed = @as(u64, destination_pitch) * surface.height;
        const minimum_pitch = @as(u64, surface.width) * 4;
        if (destination.len < needed or @as(u64, destination_pitch) < minimum_pitch) return error.BufferTooSmall;
        var y: u32 = 0;
        while (y < surface.height) : (y += 1) {
            var x: u32 = 0;
            while (x < surface.width) : (x += 1) {
                var sum: [4]u32 = .{ 0, 0, 0, 0 };
                var sample: u32 = 0;
                while (sample < surface.msaa.sampleCount()) : (sample += 1) {
                    if (surface.format == .color32) {
                        const value = try self.readColor(surface, x, y, sample);
                        sum[0] += value & 0xFF;
                        sum[1] += (value >> 8) & 0xFF;
                        sum[2] += (value >> 16) & 0xFF;
                        sum[3] += (value >> 24) & 0xFF;
                    } else {
                        const value = try self.readColor64(surface, x, y, sample);
                        sum[0] += @as(u32, @intCast((value & 0xFFFF) >> 8));
                        sum[1] += @as(u32, @intCast(((value >> 16) & 0xFFFF) >> 8));
                        sum[2] += @as(u32, @intCast(((value >> 32) & 0xFFFF) >> 8));
                        sum[3] += @as(u32, @intCast(((value >> 48) & 0xFFFF) >> 8));
                    }
                }
                const count = surface.msaa.sampleCount();
                const output = destination[@as(usize, y) * destination_pitch + @as(usize, x) * 4 ..][0..4];
                output[0] = @intCast(sum[0] / count);
                output[1] = @intCast(sum[1] / count);
                output[2] = @intCast(sum[2] / count);
                output[3] = @intCast(sum[3] / count);
            }
        }
    }
};

fn sampleCoordinates(msaa: Msaa, x: u32, y: u32, sample: u32) struct { x: u32, y: u32 } {
    return switch (msaa) {
        .x1 => .{ .x = x, .y = y },
        .x2 => .{ .x = x, .y = y * 2 + sample },
        .x4 => .{ .x = x * 2 + (sample & 1), .y = y * 2 + (sample >> 1) },
        _ => .{ .x = x, .y = y },
    };
}

fn scale(value: u32, factor: u32) u32 {
    return std.math.mul(u32, value, factor) catch std.math.maxInt(u32);
}

fn ceilDiv(value: u32, divisor: u32) u32 {
    return value / divisor + @intFromBool(value % divisor != 0);
}

test "EDRAM uses the documented 10 MiB tile geometry" {
    try std.testing.expectEqual(@as(usize, 10 * 1024 * 1024), size_bytes);
    var surface = Surface{ .base_tile = 0, .pitch_pixels = 1280, .width = 1280, .height = 720, .msaa = .x1 };
    try std.testing.expectEqual(@as(u32, 16), surface.tilePitch());
    try std.testing.expect(surface.tileCount() <= tile_count);
}

test "a multisample EDRAM clear resolves to the average color" {
    var bytes = [_]u8{0} ** size_bytes;
    const store = Store.init(&bytes);
    const surface = Surface{ .base_tile = 0, .pitch_pixels = 80, .width = 1, .height = 1, .msaa = .x4 };
    try store.writeColor(surface, 0, 0, 0, 0xFF000000);
    try store.writeColor(surface, 0, 0, 1, 0xFF0000FF);
    try store.writeColor(surface, 0, 0, 2, 0xFF00FF00);
    try store.writeColor(surface, 0, 0, 3, 0xFFFF0000);
    var output = [_]u8{0} ** 4;
    try store.resolveColor(surface, &output, 4);
    try std.testing.expectEqual(@as(u8, 0x3F), output[0]);
    try std.testing.expectEqual(@as(u8, 0x3F), output[1]);
    try std.testing.expectEqual(@as(u8, 0x3F), output[2]);
    try std.testing.expectEqual(@as(u8, 0xFF), output[3]);
}

test "EDRAM preserves 64-bit color and packed depth/stencil samples" {
    var bytes = [_]u8{0} ** size_bytes;
    const store = Store.init(&bytes);
    const color = Surface{ .base_tile = 0, .pitch_pixels = 80, .width = 1, .height = 1, .format = .color64 };
    try store.writeColor64(color, 0, 0, 0, 0xFFFF_8000_4000_0000);
    try std.testing.expectEqual(@as(u64, 0xFFFF_8000_4000_0000), try store.readColor64(color, 0, 0, 0));
    const depth = Surface{ .base_tile = 2, .pitch_pixels = 80, .width = 1, .height = 1, .format = .depth24s8 };
    try store.writeDepthStencil(depth, 0, 0, 0, 0xAB12_3456);
    try std.testing.expectEqual(@as(u32, 0xAB12_3456), try store.readDepthStencil(depth, 0, 0, 0));
}

test "EDRAM pitch follows the hardware 4x sample-space rule" {
    const x2 = Surface{ .pitch_pixels = 1280, .width = 1280, .height = 720, .msaa = .x2 };
    const x4 = Surface{ .pitch_pixels = 1280, .width = 1280, .height = 720, .msaa = .x4 };
    try std.testing.expectEqual(@as(u32, 16), x2.tilePitch());
    try std.testing.expectEqual(@as(u32, 32), x4.tilePitch());
}
