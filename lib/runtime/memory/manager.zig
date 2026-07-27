const std = @import("std");

/// Returns the byte count for a size variant. Accepts any enum type with
/// .bits8, .bits16, .bits32, .bits64 variants (e.g. x64_decoder.OperandSize).
pub fn bytesForSize(size: anytype) u8 {
    return switch (size) {
        .bits8 => 1,
        .bits16 => 2,
        .bits32 => 4,
        .bits64 => 8,
    };
}

/// Write an f64 value as an x87 extended-precision 80-bit float (10 bytes)
/// into the destination buffer.
pub fn writeExtendedFloat80(destination: []u8, value: f64) void {
    std.debug.assert(destination.len >= 10);
    @memset(destination[0..10], 0);
    const bits: u64 = @bitCast(value);
    const sign: u16 = if ((bits >> 63) != 0) 0x8000 else 0;
    const fraction = bits & 0x000F_FFFF_FFFF_FFFF;
    const exponent: u16 = @truncate((bits >> 52) & 0x7FF);
    if (exponent == 0 and fraction == 0) return;
    if (exponent == 0x7FF) {
        const significand: u64 = if (fraction == 0) 0x8000_0000_0000_0000 else 0xC000_0000_0000_0000;
        std.mem.writeInt(u64, destination[0..8], significand, .little);
        std.mem.writeInt(u16, destination[8..10], sign | 0x7FFF, .little);
        return;
    }
    var significand: u64 = 0;
    var unbiased: i32 = 0;
    if (exponent == 0) {
        const shift: u6 = @intCast(@clz(fraction));
        significand = fraction << shift;
        unbiased = -1011 - @as(i32, shift);
    } else {
        significand = (fraction | (@as(u64, 1) << 52)) << 11;
        unbiased = @as(i32, exponent) - 1023;
    }
    std.mem.writeInt(u64, destination[0..8], significand, .little);
    std.mem.writeInt(u16, destination[8..10], sign | @as(u16, @intCast(unbiased + 16383)), .little);
}

/// Read an x87 extended-precision 80-bit float (10 bytes) from the source
/// buffer and return the equivalent f64 value.
pub fn readExtendedFloat80(source: []const u8) f64 {
    std.debug.assert(source.len >= 10);
    const significand = std.mem.readInt(u64, source[0..8], .little);
    const sign_exponent = std.mem.readInt(u16, source[8..10], .little);
    const negative = (sign_exponent & 0x8000) != 0;
    const exponent = sign_exponent & 0x7FFF;
    const sign_bit: u64 = if (negative) @as(u64, 1) << 63 else 0;

    if (exponent == 0x7FFF) {
        const special_bits = if ((significand & 0x7FFF_FFFF_FFFF_FFFF) == 0)
            sign_bit | 0x7FF0_0000_0000_0000
        else
            sign_bit | 0x7FF8_0000_0000_0000;
        return @bitCast(special_bits);
    }
    if (significand == 0) return @bitCast(sign_bit);

    // Convert the explicit x87 integer bit and biased exponent to binary64.
    // Values written by writeExtendedFloat80 round-trip exactly because the
    // eleven discarded low significand bits are zero.
    const unbiased: i32 = if (exponent == 0) -16382 else @as(i32, exponent) - 16383;
    if (unbiased > 1023) return @bitCast(sign_bit | 0x7FF0_0000_0000_0000);
    if (unbiased >= -1022) {
        const binary64_exponent: u64 = @intCast(unbiased + 1023);
        const fraction = (significand >> 11) & 0x000F_FFFF_FFFF_FFFF;
        return @bitCast(sign_bit | (binary64_exponent << 52) | fraction);
    }
    if (unbiased < -1074) return @bitCast(sign_bit);
    const subnormal_shift: u6 = @intCast(-1011 - unbiased);
    const fraction = significand >> subnormal_shift;
    return @bitCast(sign_bit | (fraction & 0x000F_FFFF_FFFF_FFFF));
}

test {
    try std.testing.expectEqual(@as(u8, 1), bytesForSize(.bits8));
    try std.testing.expectEqual(@as(u8, 2), bytesForSize(.bits16));
    try std.testing.expectEqual(@as(u8, 4), bytesForSize(.bits32));
    try std.testing.expectEqual(@as(u8, 8), bytesForSize(.bits64));

    // Round-trip test for writeExtendedFloat80 / readExtendedFloat80
    var encoded: [10]u8 = undefined;
    const durations = [_]f64{ 0.001, 0.010, 0.100, 0.500, -0.001 };
    for (durations) |duration| {
        writeExtendedFloat80(&encoded, duration);
        try std.testing.expectApproxEqAbs(duration, readExtendedFloat80(&encoded), 1e-15);
    }
}
