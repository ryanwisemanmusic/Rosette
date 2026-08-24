//! MSAA resolve: sample-space to pixel-space reduction.
//!
//! A resolve reads the multisampled EDRAM surface and produces one value per
//! pixel. The reduction itself is an average; the part that goes wrong is
//! locating the samples, because 2x and 4x place them differently and the
//! placement is not symmetric.

const std = @import("std");
const contract = @import("xenia_render_target_contract");

pub const Error = error{
    /// The destination cannot hold the resolved pixels.
    DestinationTooSmall,
    /// The source does not hold the samples the mode implies.
    SourceTooSmall,
    DegenerateExtent,
};

/// Where one sample of a pixel sits in sample space.
///
/// 2x stacks its two samples vertically; 4x uses a 2x2 grid. A resolve that
/// assumes a horizontal pair for 2x reads a neighbouring pixel's sample and
/// the image comes out horizontally smeared — a plausible-looking image, which
/// is why the offsets are stated as data rather than derived inline.
pub fn sampleOffset(msaa: contract.Msaa, sample: u32) struct { x: u32, y: u32 } {
    return switch (msaa) {
        .x1 => .{ .x = 0, .y = 0 },
        .x2 => .{ .x = 0, .y = sample & 1 },
        .x4 => .{ .x = sample & 1, .y = (sample >> 1) & 1 },
    };
}

/// Samples per pixel for a mode.
pub fn samplesPerPixel(msaa: contract.Msaa) u32 {
    return msaa.sampleCount();
}

/// The sample-space index of one sample of one pixel.
pub fn sampleIndex(
    msaa: contract.Msaa,
    pixel_x: u32,
    pixel_y: u32,
    sample: u32,
    sample_pitch: u32,
) u32 {
    const offset = sampleOffset(msaa, sample);
    const sx = pixel_x * msaa.widthScale() + offset.x;
    const sy = pixel_y * msaa.heightScale() + offset.y;
    return sy * sample_pitch + sx;
}

/// Average a pixel's samples.
///
/// Averaging in `u32` per channel and dividing once: averaging in `u8` would
/// overflow on the second sample and produce a dark, wrapped pixel.
pub fn resolvePixel(samples: []const u32) u32 {
    if (samples.len == 0) return 0;
    var accumulate: [4]u32 = @splat(0);
    for (samples) |sample| {
        accumulate[0] += (sample >> 24) & 0xFF;
        accumulate[1] += (sample >> 16) & 0xFF;
        accumulate[2] += (sample >> 8) & 0xFF;
        accumulate[3] += sample & 0xFF;
    }
    const count: u32 = @intCast(samples.len);
    return ((accumulate[0] / count) << 24) |
        ((accumulate[1] / count) << 16) |
        ((accumulate[2] / count) << 8) |
        (accumulate[3] / count);
}

/// Resolve a whole surface.
pub fn resolveSurface(
    msaa: contract.Msaa,
    source: []const u32,
    sample_pitch: u32,
    destination: []u32,
    width: u32,
    height: u32,
) Error!void {
    if (width == 0 or height == 0) return error.DegenerateExtent;
    if (destination.len < @as(usize, width) * height) return error.DestinationTooSmall;

    const needed_rows = height * msaa.heightScale();
    if (source.len < @as(usize, sample_pitch) * needed_rows) return error.SourceTooSmall;

    const count = samplesPerPixel(msaa);
    var y: u32 = 0;
    while (y < height) : (y += 1) {
        var x: u32 = 0;
        while (x < width) : (x += 1) {
            var gathered: [4]u32 = undefined;
            var sample: u32 = 0;
            while (sample < count) : (sample += 1) {
                gathered[sample] = source[sampleIndex(msaa, x, y, sample, sample_pitch)];
            }
            destination[y * width + x] = resolvePixel(gathered[0..count]);
        }
    }
}

test "2x samples stack vertically, not horizontally" {
    // A horizontal pair reads a neighbouring pixel's sample, and the image
    // comes out smeared sideways — plausible enough to be blamed on filtering.
    try std.testing.expectEqual(@as(u32, 0), sampleOffset(.x2, 0).x);
    try std.testing.expectEqual(@as(u32, 0), sampleOffset(.x2, 0).y);
    try std.testing.expectEqual(@as(u32, 0), sampleOffset(.x2, 1).x);
    try std.testing.expectEqual(@as(u32, 1), sampleOffset(.x2, 1).y);
}

test "4x samples form a 2x2 grid" {
    try std.testing.expectEqual(@as(u32, 0), sampleOffset(.x4, 0).x);
    try std.testing.expectEqual(@as(u32, 0), sampleOffset(.x4, 0).y);
    try std.testing.expectEqual(@as(u32, 1), sampleOffset(.x4, 1).x);
    try std.testing.expectEqual(@as(u32, 0), sampleOffset(.x4, 1).y);
    try std.testing.expectEqual(@as(u32, 0), sampleOffset(.x4, 2).x);
    try std.testing.expectEqual(@as(u32, 1), sampleOffset(.x4, 2).y);
    try std.testing.expectEqual(@as(u32, 1), sampleOffset(.x4, 3).x);
    try std.testing.expectEqual(@as(u32, 1), sampleOffset(.x4, 3).y);
}

test "1x has one sample at the origin" {
    try std.testing.expectEqual(@as(u32, 1), samplesPerPixel(.x1));
    try std.testing.expectEqual(@as(u32, 0), sampleOffset(.x1, 0).x);
    try std.testing.expectEqual(@as(u32, 0), sampleOffset(.x1, 0).y);
}

test "averaging does not overflow a channel" {
    // Accumulating in u8 wraps on the second sample and produces a dark,
    // wrapped pixel — which reads as a lighting bug.
    const white: u32 = 0xFFFFFFFF;
    try std.testing.expectEqual(white, resolvePixel(&[_]u32{ white, white, white, white }));

    // Half black, half white averages to mid grey, not to zero.
    const black: u32 = 0x00000000;
    const grey = resolvePixel(&[_]u32{ white, black });
    try std.testing.expectEqual(@as(u32, 0x7F7F7F7F), grey);
}

test "channels average independently" {
    const red: u32 = 0xFF0000FF;
    const blue: u32 = 0xFF0000FF;
    try std.testing.expectEqual(red, resolvePixel(&[_]u32{ red, blue }));

    const mixed = resolvePixel(&[_]u32{ 0xFF000000, 0x00FF0000 });
    try std.testing.expectEqual(@as(u32, 0x7F7F0000), mixed);
}

test "an empty sample set resolves to zero rather than dividing by zero" {
    try std.testing.expectEqual(@as(u32, 0), resolvePixel(&[_]u32{}));
}

test "a 1x resolve is a copy" {
    const source = [_]u32{ 1, 2, 3, 4 };
    var destination: [4]u32 = undefined;
    try resolveSurface(.x1, &source, 2, &destination, 2, 2);
    try std.testing.expectEqualSlices(u32, &source, &destination);
}

test "a 2x resolve averages vertical neighbours" {
    // Sample pitch 2, four sample rows for two pixel rows.
    const source = [_]u32{
        0xFFFFFFFF, 0xFFFFFFFF,
        0x00000000, 0x00000000,
        0xFFFFFFFF, 0xFFFFFFFF,
        0xFFFFFFFF, 0xFFFFFFFF,
    };
    var destination: [4]u32 = undefined;
    try resolveSurface(.x2, &source, 2, &destination, 2, 2);
    // First pixel row averages rows 0 and 1: mid grey.
    try std.testing.expectEqual(@as(u32, 0x7F7F7F7F), destination[0]);
    try std.testing.expectEqual(@as(u32, 0x7F7F7F7F), destination[1]);
    // Second averages rows 2 and 3: both white.
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), destination[2]);
}

test "a 4x resolve averages a 2x2 block" {
    const source = [_]u32{
        0xFFFFFFFF, 0x00000000,
        0x00000000, 0xFFFFFFFF,
    };
    var destination: [1]u32 = undefined;
    try resolveSurface(.x4, &source, 2, &destination, 1, 1);
    try std.testing.expectEqual(@as(u32, 0x7F7F7F7F), destination[0]);
}

test "an undersized destination is refused before any write" {
    const source = [_]u32{0} ** 16;
    var destination: [1]u32 = undefined;
    try std.testing.expectError(
        error.DestinationTooSmall,
        resolveSurface(.x1, &source, 4, &destination, 4, 4),
    );
}

test "an undersized source is refused rather than read past" {
    // The bound accounts for MSAA expansion: a 2x resolve needs twice the
    // sample rows, and reading past the end is a use of unmapped EDRAM.
    const source = [_]u32{0} ** 4;
    var destination: [4]u32 = undefined;
    try std.testing.expectError(
        error.SourceTooSmall,
        resolveSurface(.x2, &source, 2, &destination, 2, 2),
    );
    // The same source is sufficient without expansion.
    try resolveSurface(.x1, &source, 2, &destination, 2, 2);
}

test "a degenerate extent is refused" {
    const source = [_]u32{0} ** 4;
    var destination: [4]u32 = undefined;
    try std.testing.expectError(error.DegenerateExtent, resolveSurface(.x1, &source, 2, &destination, 0, 2));
    try std.testing.expectError(error.DegenerateExtent, resolveSurface(.x1, &source, 2, &destination, 2, 0));
}

test "sample indices follow the mode's expansion" {
    // 4x expands both axes, so pixel (1,1) sample 0 sits at sample (2,2).
    try std.testing.expectEqual(@as(u32, 2 * 8 + 2), sampleIndex(.x4, 1, 1, 0, 8));
    // 2x expands height only, so pixel (1,1) sample 0 sits at sample (1,2).
    try std.testing.expectEqual(@as(u32, 2 * 8 + 1), sampleIndex(.x2, 1, 1, 0, 8));
}

test "the resolver covers every mode the console offers" {
    // If the contract's ceiling ever rose above what sampleOffset handles,
    // the extra samples would silently resolve from the wrong coordinates.
    try std.testing.expectEqual(contract.max_msaa_samples, samplesPerPixel(.x4));
    const modes = [_]contract.Msaa{ .x1, .x2, .x4 };
    for (modes) |mode| {
        var sample: u32 = 0;
        while (sample < samplesPerPixel(mode)) : (sample += 1) {
            const offset = sampleOffset(mode, sample);
            try std.testing.expect(offset.x < mode.widthScale());
            try std.testing.expect(offset.y < mode.heightScale());
        }
    }
}
