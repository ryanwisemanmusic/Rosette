const std = @import("std");

/// Packed integer operations supported by the SIMD execution engine.
pub const PackedIntegerOperation = enum { add, sub, mul_low };

/// Multiplies unsigned even-indexed dword lanes from two 16-byte vectors,
/// producing 64-bit results in the corresponding qword lanes.
pub fn multiplyUnsignedEvenDwords(lhs: [16]u8, rhs: [16]u8) [16]u8 {
    var result = [_]u8{0} ** 16;
    for (0..2) |lane| {
        const source_offset = lane * 8;
        const destination_offset = lane * 8;
        const left = std.mem.readInt(u32, lhs[source_offset..][0..4], .little);
        const right = std.mem.readInt(u32, rhs[source_offset..][0..4], .little);
        std.mem.writeInt(u64, result[destination_offset..][0..8], @as(u64, left) * @as(u64, right), .little);
    }
    return result;
}

/// Shuffles 32-bit dword lanes according to a control byte.
/// Each pair of bits in the control byte selects a source lane (0-3)
/// for the corresponding destination lane.
pub fn shufflePackedDwords(source: [16]u8, control: u8) [16]u8 {
    var result: [16]u8 = undefined;
    for (0..4) |destination_lane| {
        const shift: u3 = @intCast(destination_lane * 2);
        const source_lane = (control >> shift) & 0x03;
        const destination_offset = destination_lane * 4;
        const source_offset = @as(usize, source_lane) * 4;
        @memcpy(result[destination_offset..][0..4], source[source_offset..][0..4]);
    }
    return result;
}

/// Implements one 128-bit lane of VSHUFPS. The low two destination dwords
/// are selected from `lhs`, and the high two are selected from `rhs`.
pub fn shufflePackedSingles(lhs: [16]u8, rhs: [16]u8, control: u8) [16]u8 {
    var result: [16]u8 = undefined;
    for (0..4) |destination_lane| {
        const shift: u3 = @intCast(destination_lane * 2);
        const selected_lane = (control >> shift) & 0x03;
        const source = if (destination_lane < 2) lhs else rhs;
        const destination_offset = destination_lane * 4;
        const source_offset = @as(usize, selected_lane) * 4;
        @memcpy(result[destination_offset..][0..4], source[source_offset..][0..4]);
    }
    return result;
}

/// Interleaves the low qwords of two 16-byte vectors.
pub fn unpackLowQwords(lhs: [16]u8, rhs: [16]u8) [16]u8 {
    var result: [16]u8 = undefined;
    @memcpy(result[0..8], lhs[0..8]);
    @memcpy(result[8..16], rhs[0..8]);
    return result;
}

/// Blends 16-bit word lanes from two vectors using an 8-bit control mask.
/// Each bit selects between lhs (0) and rhs (1) for the corresponding word lane.
pub fn blendPackedWords(lhs: [16]u8, rhs: [16]u8, control: u8) [16]u8 {
    var result: [16]u8 = undefined;
    for (0..8) |lane| {
        const offset = lane * 2;
        const source = if (control & (@as(u8, 1) << @intCast(lane)) != 0) rhs else lhs;
        @memcpy(result[offset..][0..2], source[offset..][0..2]);
    }
    return result;
}

/// Variable-blend (VBLENDVPS/VBLENDVPD/VPBLENDVB): selects each lane from
/// `lhs` (SRC1) or `rhs` (SRC2) based on the most-significant bit of the
/// corresponding lane of the `mask` vector. A mask lane MSB of 1 selects the
/// rhs lane, 0 selects the lhs lane.
pub fn blendPackedElements(lhs: [16]u8, rhs: [16]u8, mask: [16]u8, lane_bits: u8) [16]u8 {
    var result: [16]u8 = undefined;
    switch (lane_bits) {
        8 => for (0..16) |lane| {
            result[lane] = if (mask[lane] & 0x80 != 0) rhs[lane] else lhs[lane];
        },
        16 => for (0..8) |lane| {
            const offset = lane * 2;
            const select_rhs = std.mem.readInt(u16, mask[offset..][0..2], .little) & 0x8000 != 0;
            const source = if (select_rhs) rhs else lhs;
            @memcpy(result[offset..][0..2], source[offset..][0..2]);
        },
        32 => for (0..4) |lane| {
            const offset = lane * 4;
            const select_rhs = std.mem.readInt(u32, mask[offset..][0..4], .little) & 0x80000000 != 0;
            const source = if (select_rhs) rhs else lhs;
            @memcpy(result[offset..][0..4], source[offset..][0..4]);
        },
        64 => for (0..2) |lane| {
            const offset = lane * 8;
            const select_rhs = std.mem.readInt(u64, mask[offset..][0..8], .little) & 0x8000000000000000 != 0;
            const source = if (select_rhs) rhs else lhs;
            @memcpy(result[offset..][0..8], source[offset..][0..8]);
        },
        else => unreachable,
    }
    return result;
}

/// Performs a packed integer binary operation (add, sub, or mul_low) across
/// all lanes of the specified bit width.
pub fn packedIntegerBinary(lhs: [16]u8, rhs: [16]u8, lane_bits: u8, operation: PackedIntegerOperation) [16]u8 {
    var result: [16]u8 = undefined;
    switch (lane_bits) {
        8 => for (0..16) |lane| {
            result[lane] = switch (operation) {
                .add => lhs[lane] +% rhs[lane],
                .sub => lhs[lane] -% rhs[lane],
                .mul_low => lhs[lane] *% rhs[lane],
            };
        },
        16 => for (0..8) |lane| {
            const offset = lane * 2;
            const left = std.mem.readInt(u16, lhs[offset..][0..2], .little);
            const right = std.mem.readInt(u16, rhs[offset..][0..2], .little);
            const value = switch (operation) {
                .add => left +% right,
                .sub => left -% right,
                .mul_low => left *% right,
            };
            std.mem.writeInt(u16, result[offset..][0..2], value, .little);
        },
        32 => for (0..4) |lane| {
            const offset = lane * 4;
            const left = std.mem.readInt(u32, lhs[offset..][0..4], .little);
            const right = std.mem.readInt(u32, rhs[offset..][0..4], .little);
            const value = switch (operation) {
                .add => left +% right,
                .sub => left -% right,
                .mul_low => left *% right,
            };
            std.mem.writeInt(u32, result[offset..][0..4], value, .little);
        },
        64 => for (0..2) |lane| {
            const offset = lane * 8;
            const left = std.mem.readInt(u64, lhs[offset..][0..8], .little);
            const right = std.mem.readInt(u64, rhs[offset..][0..8], .little);
            const value = switch (operation) {
                .add => left +% right,
                .sub => left -% right,
                .mul_low => left *% right,
            };
            std.mem.writeInt(u64, result[offset..][0..8], value, .little);
        },
        else => unreachable,
    }
    return result;
}

/// Performs a logical left or right shift on each element of a packed vector.
/// Elements are shifted independently within their lanes (16, 32, or 64 bits).
pub fn shiftPackedElements(source: [16]u8, lane_bits: u8, count: u64, left: bool) [16]u8 {
    var result = [_]u8{0} ** 16;
    if (count >= lane_bits) return result;
    switch (lane_bits) {
        16 => for (0..8) |lane| {
            const offset = lane * 2;
            const value = std.mem.readInt(u16, source[offset..][0..2], .little);
            std.mem.writeInt(u16, result[offset..][0..2], if (left) value << @intCast(count) else value >> @intCast(count), .little);
        },
        32 => for (0..4) |lane| {
            const offset = lane * 4;
            const value = std.mem.readInt(u32, source[offset..][0..4], .little);
            std.mem.writeInt(u32, result[offset..][0..4], if (left) value << @intCast(count) else value >> @intCast(count), .little);
        },
        64 => for (0..2) |lane| {
            const offset = lane * 8;
            const value = std.mem.readInt(u64, source[offset..][0..8], .little);
            std.mem.writeInt(u64, result[offset..][0..8], if (left) value << @intCast(count) else value >> @intCast(count), .little);
        },
        else => unreachable,
    }
    return result;
}

/// Performs a byte-wise logical shift on the entire 16-byte vector.
pub fn shiftPackedBytes(source: [16]u8, count: u64, left: bool) [16]u8 {
    var result = [_]u8{0} ** 16;
    if (count >= 16) return result;
    const amount: usize = @intCast(count);
    if (left) {
        @memcpy(result[amount..], source[0 .. 16 - amount]);
    } else {
        @memcpy(result[0 .. 16 - amount], source[amount..]);
    }
    return result;
}

test "packed integer operations round-trip" {
    const a = [_]u8{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 };
    const b = [_]u8{ 16, 15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1 };

    // Addition: 8-bit lanes
    const sum8 = packedIntegerBinary(a, b, 8, .add);
    try std.testing.expectEqual(@as(u8, 17), sum8[0]);
    try std.testing.expectEqual(@as(u8, 17), sum8[15]);

    // Subtraction: 16-bit lanes
    const sub16 = packedIntegerBinary(a, b, 16, .sub);
    try std.testing.expectEqual(@as(u16, 0xFFF0), std.mem.readInt(u16, sub16[0..2], .little));

    // Shift left 16-bit lanes by 1
    const shifted = shiftPackedElements(a, 16, 1, true);
    try std.testing.expectEqual(@as(u16, (1 << 1) | (2 << 9)), std.mem.readInt(u16, shifted[0..2], .little));

    // Shift right: all zeros
    const shifted64 = shiftPackedElements(a, 64, 64, false);
    try std.testing.expectEqual(@as(u64, 0), std.mem.readInt(u64, shifted64[0..8], .little));
}

test "VSHUFPS selects low lanes from lhs and high lanes from rhs" {
    var lhs = [_]u8{0} ** 16;
    var rhs = [_]u8{0} ** 16;
    for (0..4) |lane| {
        std.mem.writeInt(u32, lhs[lane * 4 ..][0..4], @intCast(10 + lane), .little);
        std.mem.writeInt(u32, rhs[lane * 4 ..][0..4], @intCast(20 + lane), .little);
    }

    const shuffled = shufflePackedSingles(lhs, rhs, 0x93);
    try std.testing.expectEqual(@as(u32, 13), std.mem.readInt(u32, shuffled[0..4], .little));
    try std.testing.expectEqual(@as(u32, 10), std.mem.readInt(u32, shuffled[4..8], .little));
    try std.testing.expectEqual(@as(u32, 21), std.mem.readInt(u32, shuffled[8..12], .little));
    try std.testing.expectEqual(@as(u32, 22), std.mem.readInt(u32, shuffled[12..16], .little));
}
