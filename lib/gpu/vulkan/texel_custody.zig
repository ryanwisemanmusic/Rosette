//! Bounded lookup-table evidence; interpreting bytes is not shader correctness.
//!
//! Xenia applies the console's display gamma ramp on the GPU through two
//! uniform texel buffer views: a 256-entry `A2B10G10R10_UNORM_PACK32` table
//! for 8-bit-per-channel front buffers, and a 128-segment piecewise-linear
//! (PWL) `R16G16_UINT` table of (base, delta) pairs for 10-bit front buffers.
//! The bytes are the title's choice of transfer function, but Xenia seeds
//! both tables with a linear ramp before any title writes them, so a table
//! that still reads exactly as that seed says the title's own programming
//! never reached the command processor - which for a title that renders its
//! final pass into a 7e3 floating-point buffer and relies on the ramp to
//! turn the bit patterns into intensities is the difference between a
//! picture and a very dark one.
//!
//! This module decodes what the table *does*: whether it is Xenia's default,
//! and what it maps a few reference inputs to. It does not decide whether
//! that is right; that verdict belongs to the brightness ladder that reads
//! the images on either side of the ramp.
const std = @import("std");

/// The reference inputs the shape is sampled at, as the 10-bit patterns the
/// PWL path indexes with. `0x180` is the bit pattern of 1.0 in the Xenos 7e3
/// floating-point framebuffer format (exponent 3, mantissa 0), so a 7e3 title
/// with a ramp that maps it near white is displaying its HDR white correctly
/// and one with a linear ramp is displaying it at 37% grey.
pub const input_max: u16 = 0x3FF;
pub const input_7e3_one: u16 = 0x180;
pub const input_mid: u16 = 0x200;

pub const Shape = enum {
    /// Fewer bytes than the format's table needs, so nothing can be said.
    unknown_size,
    /// Every byte is zero: the ramp maps everything to black.
    zero,
    /// Exactly the linear ramp Xenia's `CommandProcessor` constructor seeds.
    xenia_default_linear,
    /// Something the title (or a later Xenia write) programmed.
    programmed,

    pub fn label(self: Shape) []const u8 {
        return switch (self) {
            .unknown_size => "unknown_size",
            .zero => "zero",
            .xenia_default_linear => "xenia_default_linear",
            .programmed => "programmed",
        };
    }
};

pub const Stats = struct {
    hash: u64 = 14_695_981_039_346_656_037,
    nonzero_bytes: u32 = 0,
    entries: u32 = 0,
    min: [3]u32 = @splat(std.math.maxInt(u32)),
    max: [3]u32 = @splat(0),
    shape: Shape = .unknown_size,
    /// The red channel's output on a 0..1023 scale for the reference inputs.
    /// For the 256-entry table the inputs are the same patterns divided by
    /// four, since that path indexes with an 8-bit value.
    out_max: u16 = 0,
    out_7e3_one: u16 = 0,
    out_mid: u16 = 0,
};

/// Number of 32-bit words a complete table of each format holds.
pub fn tableEntries(format: u32) ?u32 {
    return switch (format) {
        64 => 256, // A2B10G10R10_UNORM: one word per 8-bit input
        81 => 384, // R16G16_UINT: 128 segments x 3 channels of (base, delta)
        else => null,
    };
}

pub fn analyze(bytes: []const u8, format: u32) !Stats {
    if (bytes.len == 0 or bytes.len > 4096 or bytes.len % 4 != 0) return error.InvalidTable;
    const table_entries = tableEntries(format) orelse return error.UnsupportedFormat;
    var stats = Stats{};
    for (bytes) |byte| {
        stats.hash = (stats.hash ^ byte) *% 1_099_511_628_211;
        if (byte != 0) stats.nonzero_bytes += 1;
    }
    stats.entries = @intCast(bytes.len / 4);
    var offset: usize = 0;
    while (offset < bytes.len) : (offset += 4) {
        const packed_word = std.mem.readInt(u32, bytes[offset..][0..4], .little);
        const components: [3]u32 = switch (format) {
            64 => .{ packed_word & 1023, (packed_word >> 10) & 1023, (packed_word >> 20) & 1023 }, // A2B10G10R10_UNORM
            81 => .{ packed_word & 65535, packed_word >> 16, 0 }, // R16G16_UINT: PWL base/delta
            else => unreachable,
        };
        for (components, 0..) |value, channel| {
            stats.min[channel] = @min(stats.min[channel], value);
            stats.max[channel] = @max(stats.max[channel], value);
        }
    }
    if (stats.entries < table_entries) return stats;
    if (stats.nonzero_bytes == 0) {
        stats.shape = .zero;
        return stats;
    }
    switch (format) {
        64 => {
            stats.out_max = tableOutput(bytes, input_max >> 2);
            stats.out_7e3_one = tableOutput(bytes, input_7e3_one >> 2);
            stats.out_mid = tableOutput(bytes, input_mid >> 2);
            stats.shape = if (tableIsXeniaDefault(bytes)) .xenia_default_linear else .programmed;
        },
        81 => {
            stats.out_max = pwlOutput(bytes, input_max);
            stats.out_7e3_one = pwlOutput(bytes, input_7e3_one);
            stats.out_mid = pwlOutput(bytes, input_mid);
            stats.shape = if (pwlIsXeniaDefault(bytes)) .xenia_default_linear else .programmed;
        },
        else => unreachable,
    }
    return stats;
}

fn word(bytes: []const u8, index: usize) u32 {
    return std.mem.readInt(u32, bytes[index * 4 ..][0..4], .little);
}

/// Red output of the 256-entry table for an 8-bit input. Xenia packs
/// `DC_LUT_30_COLOR` as blue in bits 0-9, green in 10-19 and red in 20-29,
/// and its shader undoes that with a `.bgr` swizzle, so red is the top field.
fn tableOutput(bytes: []const u8, input: u16) u16 {
    return @intCast((word(bytes, input) >> 20) & 1023);
}

/// The 256-entry ramp `CommandProcessor::CommandProcessor` seeds: every
/// channel of entry `i` holds `i * 1023 / 255`.
fn tableIsXeniaDefault(bytes: []const u8) bool {
    for (0..256) |i| {
        const value: u32 = @intCast(i * 0x3FF / 0xFF);
        if (word(bytes, i) != (value | (value << 10) | (value << 20))) return false;
    }
    return true;
}

/// Red output of the PWL ramp for a 10-bit input, as Xenia's
/// `apply_gamma_pwl` shader computes it: segment `input >> 3`, then
/// `(base + (input & 7) * delta / 8) / (64 * 1023)` normalized, here scaled
/// back to 0..1023 and saturated.
fn pwlOutput(bytes: []const u8, input: u16) u16 {
    const segment: usize = @as(usize, input >> 3);
    const entry = word(bytes, segment * 3);
    const base: u32 = entry & 0xFFFF;
    const delta: u32 = entry >> 16;
    const value = (base + ((@as(u32, input) & 7) * delta) / 8) / 64;
    return @intCast(@min(value, 1023));
}

/// The PWL ramp Xenia seeds: segment `i` has `base = (i * 65535 / 127) & ~63`
/// and `delta = 0x200` (zero on the last segment), identical in all three
/// channels. Applied through the shader above, it is a straight line from
/// black to white over the 128 segments.
fn pwlIsXeniaDefault(bytes: []const u8) bool {
    for (0..128) |i| {
        const base: u32 = @intCast((i * 0xFFFF / 0x7F) & ~@as(usize, 0x3F));
        const delta: u32 = if (i < 0x7F) 0x200 else 0;
        const expected = base | (delta << 16);
        for (0..3) |channel| {
            if (word(bytes, i * 3 + channel) != expected) return false;
        }
    }
    return true;
}

fn xeniaDefaultPwl() [1536]u8 {
    var bytes: [1536]u8 = undefined;
    for (0..128) |i| {
        const base: u32 = @intCast((i * 0xFFFF / 0x7F) & ~@as(usize, 0x3F));
        const delta: u32 = if (i < 0x7F) 0x200 else 0;
        for (0..3) |channel| {
            std.mem.writeInt(u32, bytes[(i * 3 + channel) * 4 ..][0..4], base | (delta << 16), .little);
        }
    }
    return bytes;
}

fn xeniaDefaultTable() [1024]u8 {
    var bytes: [1024]u8 = undefined;
    for (0..256) |i| {
        const value: u32 = @intCast(i * 0x3FF / 0xFF);
        std.mem.writeInt(u32, bytes[i * 4 ..][0..4], value | (value << 10) | (value << 20), .little);
    }
    return bytes;
}

test "gamma custody decodes packed ten-bit channels without eight-bit truncation" {
    const packed_word: u32 = 1023 | (512 << 10) | (255 << 20);
    var bytes: [8]u8 = @splat(0);
    std.mem.writeInt(u32, bytes[4..8], packed_word, .little);
    const stats = try analyze(&bytes, 64);
    try std.testing.expectEqual([3]u32{ 1023, 512, 255 }, stats.max);
    try std.testing.expectEqual([3]u32{ 0, 0, 0 }, stats.min);
    try std.testing.expectEqual(Shape.unknown_size, stats.shape);
    const pwl = try analyze(&.{ 0x34, 0x12, 0x78, 0x56 }, 81);
    try std.testing.expectEqual([3]u32{ 0x1234, 0x5678, 0 }, pwl.max);
}

test "zero and unbounded lookup tables do not become content proof" {
    const zero = try analyze(&.{ 0, 0, 0, 0 }, 64);
    try std.testing.expectEqual(@as(u32, 0), zero.nonzero_bytes);
    try std.testing.expectError(error.InvalidTable, analyze(&.{ 1, 2, 3 }, 64));
    try std.testing.expectError(error.UnsupportedFormat, analyze(&.{ 1, 2, 3, 4 }, 44));
    const zero_full = try analyze(&([_]u8{0} ** 1536), 81);
    try std.testing.expectEqual(Shape.zero, zero_full.shape);
}

test "Xenia's default PWL ramp is recognised and reads as the identity" {
    const bytes = xeniaDefaultPwl();
    const stats = try analyze(&bytes, 81);
    try std.testing.expectEqual(Shape.xenia_default_linear, stats.shape);
    try std.testing.expectEqual(@as(u32, 65472), stats.max[0]);
    try std.testing.expectEqual(@as(u32, 512), stats.max[1]);
    // Linear: the 7e3 pattern for 1.0 comes out as the ~38% grey it is as a
    // fixed-point value (segment 48 of 127), which is exactly the dark
    // picture a 7e3 title shows when its own ramp never arrived.
    try std.testing.expectEqual(@as(u16, 387), stats.out_7e3_one);
    try std.testing.expectEqual(@as(u16, 516), stats.out_mid);
    try std.testing.expectEqual(@as(u16, 1023), stats.out_max);
}

test "a title-programmed PWL ramp is not the default and its outputs follow the shader" {
    var bytes = xeniaDefaultPwl();
    // Halo 3's later ramp starts with base 0, delta 0x500 for segment 0 and
    // ends with base 0xFBC0, delta 0x400 for segment 127 (register_table.inc).
    std.mem.writeInt(u32, bytes[0..4], 0x0500_0000, .little);
    std.mem.writeInt(u32, bytes[127 * 3 * 4 ..][0..4], 0x0400_FBC0, .little);
    const stats = try analyze(&bytes, 81);
    try std.testing.expectEqual(Shape.programmed, stats.shape);
    // Segment 127, sub-index 7: (0xFBC0 + 7 * 0x400 / 8) / 64 = 1021.
    try std.testing.expectEqual(@as(u16, 1021), stats.out_max);
}

test "Xenia's default 256-entry table is recognised" {
    const bytes = xeniaDefaultTable();
    const stats = try analyze(&bytes, 64);
    try std.testing.expectEqual(Shape.xenia_default_linear, stats.shape);
    try std.testing.expectEqual(@as(u16, 1023), stats.out_max);
    try std.testing.expectEqual(@as(u16, 0x60 * 0x3FF / 0xFF), stats.out_7e3_one);
    var programmed = bytes;
    std.mem.writeInt(u32, programmed[255 * 4 ..][0..4], 0, .little);
    try std.testing.expectEqual(Shape.programmed, (try analyze(&programmed, 64)).shape);
}
