const std = @import("std");
const types = @import("types.zig");

pub const BinaryOp = enum {
    add,
    sub,
    mul,
    div,
    min,
    max,
    bit_or,
    bit_xor,
    bit_and,
    bit_andnot,
    cmp,
    cmpgt,
    addsub,
    subs,
    subus,
};

pub const UnaryOp = enum {
    sqrt,
};

pub const MaskMode = enum {
    merge,
    zero,
};

pub const AesRoundOp = enum {
    enc,
    dec,
    enc_last,
    dec_last,
};

pub fn Wide(comptime bits: usize) type {
    types.validateWideWidth(bits);
    return struct {
        pub const bit_count = bits;
        pub const byte_count = bits / 8;
        pub const block_count = bits / types.VECTOR_BLOCK_BITS;

        bytes: [byte_count]u8,

        pub fn zero() @This() {
            return .{ .bytes = [_]u8{0} ** byte_count };
        }

        pub fn fromBytes(bytes: [byte_count]u8) @This() {
            return .{ .bytes = bytes };
        }

        pub fn splatByte(byte: u8) @This() {
            return .{ .bytes = [_]u8{byte} ** byte_count };
        }

        pub fn equal(self: @This(), other: @This()) bool {
            return std.mem.eql(u8, self.bytes[0..], other.bytes[0..]);
        }
    };
}

pub fn laneCount(comptime bits: usize, comptime T: type) usize {
    return types.laneCount(bits, T);
}

pub fn fromArray(comptime bits: usize, comptime T: type, array: [laneCount(bits, T)]T) Wide(bits) {
    var result = Wide(bits).zero();
    @memcpy(result.bytes[0..], std.mem.asBytes(&array));
    return result;
}

pub fn toArray(comptime bits: usize, comptime T: type, value: Wide(bits)) [laneCount(bits, T)]T {
    var result: [laneCount(bits, T)]T = undefined;
    @memcpy(std.mem.asBytes(&result), value.bytes[0..]);
    return result;
}

pub fn load(comptime bits: usize, comptime T: type, src: []const T) types.SafetyError!Wide(bits) {
    const lanes = comptime laneCount(bits, T);
    if (src.len < lanes) return types.SafetyError.BufferTooSmall;
    var tmp: [lanes]T = undefined;
    for (0..lanes) |lane| tmp[lane] = src[lane];
    return fromArray(bits, T, tmp);
}

pub fn store(comptime bits: usize, comptime T: type, dst: []T, value: Wide(bits)) types.SafetyError!void {
    const lanes = comptime laneCount(bits, T);
    if (dst.len < lanes) return types.SafetyError.BufferTooSmall;
    const tmp = toArray(bits, T, value);
    for (0..lanes) |lane| dst[lane] = tmp[lane];
}

pub fn loadBytes(comptime bits: usize, src: []const u8) types.SafetyError!Wide(bits) {
    const byte_count = bits / 8;
    if (src.len < byte_count) return types.SafetyError.BufferTooSmall;
    var result = Wide(bits).zero();
    @memcpy(result.bytes[0..], src[0..byte_count]);
    return result;
}

pub fn storeBytes(comptime bits: usize, dst: []u8, value: Wide(bits)) types.SafetyError!void {
    const byte_count = bits / 8;
    if (dst.len < byte_count) return types.SafetyError.BufferTooSmall;
    @memcpy(dst[0..byte_count], value.bytes[0..]);
}

pub fn loadBytesAligned(comptime bits: usize, src: []const u8, alignment: types.Alignment) types.SafetyError!Wide(bits) {
    const required = alignment.bytes();
    if (required > 1 and @intFromPtr(src.ptr) % required != 0) return types.SafetyError.MisalignedMemory;
    return loadBytes(bits, src);
}

pub fn storeBytesAligned(comptime bits: usize, dst: []u8, value: Wide(bits), alignment: types.Alignment) types.SafetyError!void {
    const required = alignment.bytes();
    if (required > 1 and @intFromPtr(dst.ptr) % required != 0) return types.SafetyError.MisalignedMemory;
    try storeBytes(bits, dst, value);
}

fn zeroValue(comptime T: type) T {
    return switch (@typeInfo(T)) {
        .float => @as(T, 0.0),
        .int => @as(T, 0),
        else => @compileError("CLEO only supports integer and float lane types"),
    };
}

fn applyBinaryScalar(comptime T: type, lhs: T, rhs: T, comptime op: BinaryOp, lane: usize) T {
    return switch (op) {
        .add => if (@typeInfo(T) == .float) lhs + rhs else lhs +% rhs,
        .sub => if (@typeInfo(T) == .float) lhs - rhs else lhs -% rhs,
        .mul => if (@typeInfo(T) == .float) lhs * rhs else lhs *% rhs,
        .div => if (@typeInfo(T) == .float) lhs / rhs else @divTrunc(lhs, rhs),
        .min => if (lhs < rhs) lhs else rhs,
        .max => if (lhs > rhs) lhs else rhs,
        .bit_or => lhs | rhs,
        .bit_xor => lhs ^ rhs,
        .bit_and => lhs & rhs,
        .bit_andnot => ~lhs & rhs,
        .cmp => blk: {
            const IntT = std.meta.Int(.unsigned, @bitSizeOf(T));
            break :blk @bitCast(if (lhs == rhs) ~@as(IntT, 0) else @as(IntT, 0));
        },
        .cmpgt => blk: {
            const IntT = std.meta.Int(.unsigned, @bitSizeOf(T));
            break :blk @bitCast(if (lhs > rhs) ~@as(IntT, 0) else @as(IntT, 0));
        },
        .subs => blk: {
            const WideT = std.meta.Int(.signed, @bitSizeOf(T) * 2);
            const big: WideT = @as(WideT, lhs) - @as(WideT, rhs);
            break :blk @intCast(std.math.clamp(big, std.math.minInt(T), std.math.maxInt(T)));
        },
        .subus => blk: {
            break :blk if (lhs >= rhs) lhs - rhs else @as(T, 0);
        },
        .addsub => if ((lane & 1) == 0)
            (if (@typeInfo(T) == .float) lhs - rhs else lhs -% rhs)
        else
            (if (@typeInfo(T) == .float) lhs + rhs else lhs +% rhs),
    };
}

fn applyUnaryScalar(comptime T: type, value: T, comptime op: UnaryOp) T {
    return switch (op) {
        .sqrt => if (@typeInfo(T) == .float) @sqrt(value) else @compileError("CLEO sqrt requires float lanes"),
    };
}

pub fn mapUnary(comptime bits: usize, comptime T: type, src: Wide(bits), comptime op: UnaryOp) Wide(bits) {
    const lanes = comptime laneCount(bits, T);
    const input = toArray(bits, T, src);
    var out: [lanes]T = undefined;
    for (0..lanes) |lane| out[lane] = applyUnaryScalar(T, input[lane], op);
    return fromArray(bits, T, out);
}

pub fn mapUnaryMasked(comptime bits: usize, comptime T: type, merge: Wide(bits), src: Wide(bits), mask: u64, mode: MaskMode, comptime op: UnaryOp) Wide(bits) {
    const computed = mapUnary(bits, T, src, op);
    return applyLaneMask(bits, T, merge, computed, mask, mode);
}

pub fn mapBinary(comptime bits: usize, comptime T: type, lhs: Wide(bits), rhs: Wide(bits), comptime op: BinaryOp) Wide(bits) {
    const lanes = comptime laneCount(bits, T);
    const a = toArray(bits, T, lhs);
    const b = toArray(bits, T, rhs);
    var out: [lanes]T = undefined;
    for (0..lanes) |lane| out[lane] = applyBinaryScalar(T, a[lane], b[lane], op, lane);
    return fromArray(bits, T, out);
}

pub fn mapBinaryMasked(comptime bits: usize, comptime T: type, merge: Wide(bits), lhs: Wide(bits), rhs: Wide(bits), mask: u64, mode: MaskMode, comptime op: BinaryOp) Wide(bits) {
    const lanes = comptime laneCount(bits, T);
    const base = toArray(bits, T, merge);
    const a = toArray(bits, T, lhs);
    const b = toArray(bits, T, rhs);
    var out: [lanes]T = undefined;
    for (0..lanes) |lane| {
        const bit = (@as(u64, 1) << @intCast(lane));
        if ((mask & bit) != 0) {
            out[lane] = applyBinaryScalar(T, a[lane], b[lane], op, lane);
        } else {
            out[lane] = if (mode == .zero) zeroValue(T) else base[lane];
        }
    }
    return fromArray(bits, T, out);
}

pub fn applyLaneMask(comptime bits: usize, comptime T: type, merge: Wide(bits), value: Wide(bits), mask: u64, mode: MaskMode) Wide(bits) {
    const lanes = comptime laneCount(bits, T);
    const base = toArray(bits, T, merge);
    const data = toArray(bits, T, value);
    var out: [lanes]T = undefined;
    for (0..lanes) |lane| {
        const bit = (@as(u64, 1) << @intCast(lane));
        out[lane] = if ((mask & bit) != 0)
            data[lane]
        else if (mode == .zero)
            zeroValue(T)
        else
            base[lane];
    }
    return fromArray(bits, T, out);
}

fn allOnes(comptime T: type) T {
    if (@typeInfo(T) != .int) @compileError("all-ones compare masks use integer lane views");
    return ~@as(T, 0);
}

fn compareFloat(comptime T: type, lhs: T, rhs: T, immediate: u8) bool {
    if (@typeInfo(T) != .float) @compileError("SIMD compare predicates use float lanes");
    const unordered = std.math.isNan(lhs) or std.math.isNan(rhs);
    return switch (immediate & 0x7) {
        0 => !unordered and lhs == rhs,
        1 => !unordered and lhs < rhs,
        2 => !unordered and lhs <= rhs,
        3 => unordered,
        4 => unordered or lhs != rhs,
        5 => unordered or !(lhs < rhs),
        6 => unordered or !(lhs <= rhs),
        7 => !unordered,
        else => unreachable,
    };
}

pub fn cmpImmediatePS(comptime bits: usize, lhs: Wide(bits), rhs: Wide(bits), immediate: u8) Wide(bits) {
    const lanes = comptime laneCount(bits, f32);
    const a = toArray(bits, f32, lhs);
    const b = toArray(bits, f32, rhs);
    var out: [lanes]u32 = undefined;
    for (0..lanes) |lane| out[lane] = if (compareFloat(f32, a[lane], b[lane], immediate)) allOnes(u32) else 0;
    return fromArray(bits, u32, out);
}

pub fn cmpImmediatePD(comptime bits: usize, lhs: Wide(bits), rhs: Wide(bits), immediate: u8) Wide(bits) {
    const lanes = comptime laneCount(bits, f64);
    const a = toArray(bits, f64, lhs);
    const b = toArray(bits, f64, rhs);
    var out: [lanes]u64 = undefined;
    for (0..lanes) |lane| out[lane] = if (compareFloat(f64, a[lane], b[lane], immediate)) allOnes(u64) else 0;
    return fromArray(bits, u64, out);
}

pub fn cmpImmediatePSMasked(comptime bits: usize, merge: Wide(bits), lhs: Wide(bits), rhs: Wide(bits), immediate: u8, mask: u64, mode: MaskMode) Wide(bits) {
    const compared = cmpImmediatePS(bits, lhs, rhs, immediate);
    return applyLaneMask(bits, u32, merge, compared, mask, mode);
}

pub fn cmpImmediatePDMasked(comptime bits: usize, merge: Wide(bits), lhs: Wide(bits), rhs: Wide(bits), immediate: u8, mask: u64, mode: MaskMode) Wide(bits) {
    const compared = cmpImmediatePD(bits, lhs, rhs, immediate);
    return applyLaneMask(bits, u64, merge, compared, mask, mode);
}

fn immediateBit(immediate: u8, lane: usize) bool {
    if (lane >= 8) return false;
    const shift: u3 = @intCast(lane);
    return ((immediate >> shift) & 1) != 0;
}

fn immediateTwoBits(immediate: u8, shift_bits: usize) usize {
    const shift: u3 = @intCast(shift_bits & 7);
    return @intCast((immediate >> shift) & 0x3);
}

fn signBitMask(comptime T: type) T {
    if (@typeInfo(T) != .int) @compileError("variable blend masks must use integer lane views");
    return @as(T, 1) << (@bitSizeOf(T) - 1);
}

pub fn blendImmediate(comptime bits: usize, comptime T: type, lhs: Wide(bits), rhs: Wide(bits), immediate: u8) Wide(bits) {
    const lanes = comptime laneCount(bits, T);
    const a = toArray(bits, T, lhs);
    const b = toArray(bits, T, rhs);
    var out: [lanes]T = undefined;
    for (0..lanes) |lane| out[lane] = if (immediateBit(immediate, lane)) b[lane] else a[lane];
    return fromArray(bits, T, out);
}

pub fn blendVariable(comptime bits: usize, comptime T: type, lhs: Wide(bits), rhs: Wide(bits), selector: Wide(bits)) Wide(bits) {
    const lanes = comptime laneCount(bits, T);
    const sign = comptime signBitMask(T);
    const a = toArray(bits, T, lhs);
    const b = toArray(bits, T, rhs);
    const select = toArray(bits, T, selector);
    var out: [lanes]T = undefined;
    for (0..lanes) |lane| out[lane] = if ((select[lane] & sign) != 0) b[lane] else a[lane];
    return fromArray(bits, T, out);
}

pub fn shuffleImmediatePS(comptime bits: usize, lhs: Wide(bits), rhs: Wide(bits), immediate: u8) Wide(bits) {
    const lanes = comptime laneCount(bits, u32);
    if (lanes % 4 != 0) @compileError("SHUFPS needs 128-bit groups of four f32 lanes");
    const a = toArray(bits, u32, lhs);
    const b = toArray(bits, u32, rhs);
    var out: [lanes]u32 = undefined;
    for (0..(lanes / 4)) |block| {
        const base = block * 4;
        out[base + 0] = a[base + immediateTwoBits(immediate, 0)];
        out[base + 1] = a[base + immediateTwoBits(immediate, 2)];
        out[base + 2] = b[base + immediateTwoBits(immediate, 4)];
        out[base + 3] = b[base + immediateTwoBits(immediate, 6)];
    }
    return fromArray(bits, u32, out);
}

pub fn shuffleImmediatePD(comptime bits: usize, lhs: Wide(bits), rhs: Wide(bits), immediate: u8) Wide(bits) {
    const lanes = comptime laneCount(bits, u64);
    if (lanes % 2 != 0) @compileError("SHUFPD needs 128-bit groups of two f64 lanes");
    const a = toArray(bits, u64, lhs);
    const b = toArray(bits, u64, rhs);
    var out: [lanes]u64 = undefined;
    for (0..(lanes / 2)) |pair| {
        const base = pair * 2;
        const lhs_lane: usize = if (immediateBit(immediate, pair * 2)) 1 else 0;
        const rhs_lane: usize = if (immediateBit(immediate, pair * 2 + 1)) 1 else 0;
        out[base + 0] = a[base + lhs_lane];
        out[base + 1] = b[base + rhs_lane];
    }
    return fromArray(bits, u64, out);
}

pub fn shuffleImmediatePSMasked(comptime bits: usize, merge: Wide(bits), lhs: Wide(bits), rhs: Wide(bits), immediate: u8, mask: u64, mode: MaskMode) Wide(bits) {
    const shuffled = shuffleImmediatePS(bits, lhs, rhs, immediate);
    return applyLaneMask(bits, u32, merge, shuffled, mask, mode);
}

pub fn shuffleImmediatePDMasked(comptime bits: usize, merge: Wide(bits), lhs: Wide(bits), rhs: Wide(bits), immediate: u8, mask: u64, mode: MaskMode) Wide(bits) {
    const shuffled = shuffleImmediatePD(bits, lhs, rhs, immediate);
    return applyLaneMask(bits, u64, merge, shuffled, mask, mode);
}

pub fn dotProductPS(comptime bits: usize, lhs: Wide(bits), rhs: Wide(bits), immediate: u8) Wide(bits) {
    const lanes = comptime laneCount(bits, f32);
    if (lanes % 4 != 0) @compileError("DPPS needs 128-bit groups of four f32 lanes");
    const a = toArray(bits, f32, lhs);
    const b = toArray(bits, f32, rhs);
    var out: [lanes]f32 = undefined;
    for (0..(lanes / 4)) |block| {
        const base = block * 4;
        var sum: f32 = 0;
        for (0..4) |lane| {
            if (immediateBit(immediate, 4 + lane)) sum += a[base + lane] * b[base + lane];
        }
        for (0..4) |lane| out[base + lane] = if (immediateBit(immediate, lane)) sum else 0;
    }
    return fromArray(bits, f32, out);
}

fn bf16ToF32(value: u16) f32 {
    return @bitCast(@as(u32, value) << 16);
}

pub fn dotBF16PS(comptime bits: usize, accum: Wide(bits), lhs: Wide(bits), rhs: Wide(bits)) Wide(bits) {
    const lanes = comptime laneCount(bits, f32);
    const acc = toArray(bits, f32, accum);
    const a = toArray(bits, u16, lhs);
    const b = toArray(bits, u16, rhs);
    var out: [lanes]f32 = undefined;
    for (0..lanes) |lane| {
        const pair = lane * 2;
        out[lane] = acc[lane] +
            bf16ToF32(a[pair]) * bf16ToF32(b[pair]) +
            bf16ToF32(a[pair + 1]) * bf16ToF32(b[pair + 1]);
    }
    return fromArray(bits, f32, out);
}

pub fn dotBF16PSMasked(comptime bits: usize, merge: Wide(bits), accum: Wide(bits), lhs: Wide(bits), rhs: Wide(bits), mask: u64, mode: MaskMode) Wide(bits) {
    const dotted = dotBF16PS(bits, accum, lhs, rhs);
    return applyLaneMask(bits, f32, merge, dotted, mask, mode);
}

pub fn aesRound(comptime bits: usize, state: Wide(bits), round_key: Wide(bits), comptime op: AesRoundOp) Wide(bits) {
    if (bits % 128 != 0) @compileError("VAES rounds operate on independent 128-bit AES blocks");
    const block_count = comptime bits / 128;
    const BlockVec = std.crypto.core.aes.BlockVec(block_count);
    const state_vec = BlockVec.fromBytes(&state.bytes);
    const key_vec = BlockVec.fromBytes(&round_key.bytes);
    const out_vec = switch (op) {
        .enc => state_vec.encrypt(key_vec),
        .dec => state_vec.decrypt(key_vec),
        .enc_last => state_vec.encryptLast(key_vec),
        .dec_last => state_vec.decryptLast(key_vec),
    };
    return Wide(bits).fromBytes(out_vec.toBytes());
}

pub fn movMaskPS(comptime bits: usize, value: Wide(bits)) u32 {
    const lanes = comptime laneCount(bits, u32);
    const data = toArray(bits, u32, value);
    var result: u32 = 0;
    for (0..lanes) |lane| {
        if ((data[lane] & 0x80000000) != 0) result |= @as(u32, 1) << @intCast(lane);
    }
    return result;
}

pub fn movMaskPD(comptime bits: usize, value: Wide(bits)) u32 {
    const lanes = comptime laneCount(bits, u64);
    const data = toArray(bits, u64, value);
    var result: u32 = 0;
    for (0..lanes) |lane| {
        if ((data[lane] & 0x8000000000000000) != 0) result |= @as(u32, 1) << @intCast(lane);
    }
    return result;
}

pub fn duplicateOddF32(comptime bits: usize, value: Wide(bits)) Wide(bits) {
    const lanes = comptime laneCount(bits, u32);
    const src = toArray(bits, u32, value);
    var out: [lanes]u32 = undefined;
    for (0..lanes) |lane| {
        const odd_lane = (lane & ~@as(usize, 1)) + 1;
        out[lane] = src[odd_lane];
    }
    return fromArray(bits, u32, out);
}

pub fn duplicateEvenF32(comptime bits: usize, value: Wide(bits)) Wide(bits) {
    const lanes = comptime laneCount(bits, u32);
    const src = toArray(bits, u32, value);
    var out: [lanes]u32 = undefined;
    for (0..lanes) |lane| out[lane] = src[lane & ~@as(usize, 1)];
    return fromArray(bits, u32, out);
}

pub fn duplicateLowF64Per128(comptime bits: usize, value: Wide(bits)) Wide(bits) {
    const lanes = comptime laneCount(bits, u64);
    const src = toArray(bits, u64, value);
    var out: [lanes]u64 = undefined;
    for (0..lanes) |lane| out[lane] = src[(lane / 2) * 2];
    return fromArray(bits, u64, out);
}

test "CLEO wide values round-trip typed arrays" {
    const data = [_]f32{ 1, 2, 3, 4, 5, 6, 7, 8 };
    const value = fromArray(256, f32, data);
    try std.testing.expectEqual(data, toArray(256, f32, value));
}

test "CLEO maps 1024-bit integer lanes through 128-bit-safe storage" {
    var lhs: [32]u32 = undefined;
    var rhs: [32]u32 = undefined;
    for (0..32) |i| {
        lhs[i] = @intCast(i);
        rhs[i] = 10;
    }
    const out = mapBinary(1024, u32, fromArray(1024, u32, lhs), fromArray(1024, u32, rhs), .add);
    const got = toArray(1024, u32, out);
    try std.testing.expectEqual(@as(u32, 41), got[31]);
}

test "CLEO compares packed floats with immediate predicates" {
    const lhs = fromArray(256, f32, .{ 1, 2, 3, 4, 5, 6, 7, 8 });
    const rhs = fromArray(256, f32, .{ 1, 3, 2, 4, 6, 5, 7, 9 });
    const out = cmpImmediatePS(256, lhs, rhs, 1);
    try std.testing.expectEqual([_]u32{ 0, allOnes(u32), 0, 0, allOnes(u32), 0, 0, allOnes(u32) }, toArray(256, u32, out));
}

test "CLEO blends immediate lanes" {
    const lhs = fromArray(256, u32, .{ 1, 2, 3, 4, 5, 6, 7, 8 });
    const rhs = fromArray(256, u32, .{ 10, 20, 30, 40, 50, 60, 70, 80 });
    const out = blendImmediate(256, u32, lhs, rhs, 0b10101010);
    try std.testing.expectEqual([_]u32{ 1, 20, 3, 40, 5, 60, 7, 80 }, toArray(256, u32, out));
}

test "CLEO blends variable lanes from mask sign bits" {
    const lhs = fromArray(256, u32, .{ 1, 2, 3, 4, 5, 6, 7, 8 });
    const rhs = fromArray(256, u32, .{ 10, 20, 30, 40, 50, 60, 70, 80 });
    const selector = fromArray(256, u32, .{ 0x80000000, 0, 0x80000000, 0, 0, 0x80000000, 0, 0x80000000 });
    const out = blendVariable(256, u32, lhs, rhs, selector);
    try std.testing.expectEqual([_]u32{ 10, 2, 30, 4, 5, 60, 7, 80 }, toArray(256, u32, out));
}

test "CLEO shuffles packed single lanes per 128-bit block" {
    const lhs = fromArray(256, u32, .{ 1, 2, 3, 4, 5, 6, 7, 8 });
    const rhs = fromArray(256, u32, .{ 10, 20, 30, 40, 50, 60, 70, 80 });
    const out = shuffleImmediatePS(256, lhs, rhs, 0b01_00_11_10);
    try std.testing.expectEqual([_]u32{ 3, 4, 10, 20, 7, 8, 50, 60 }, toArray(256, u32, out));
}

test "CLEO computes DPPS per 128-bit lane group" {
    const lhs = fromArray(256, f32, .{ 1, 2, 3, 4, 5, 6, 7, 8 });
    const rhs = fromArray(256, f32, .{ 10, 20, 30, 40, 1, 2, 3, 4 });
    const out = dotProductPS(256, lhs, rhs, 0b1111_0001);
    try std.testing.expectEqual([_]f32{ 300, 0, 0, 0, 70, 0, 0, 0 }, toArray(256, f32, out));
}

test "CLEO computes BF16 dot product accumulation" {
    const acc = fromArray(256, f32, .{ 1, 2, 3, 4, 5, 6, 7, 8 });
    const ones = [_]u16{0x3f80} ** 16;
    const twos = [_]u16{0x4000} ** 16;
    const out = dotBF16PS(256, acc, fromArray(256, u16, ones), fromArray(256, u16, twos));
    try std.testing.expectEqual([_]f32{ 5, 6, 7, 8, 9, 10, 11, 12 }, toArray(256, f32, out));
}

test "CLEO applies AES rounds per 128-bit block" {
    const state = Wide(256).zero();
    const key = Wide(256).zero();
    const out = aesRound(256, state, key, .enc_last);
    const lanes = toArray(256, u8, out);
    try std.testing.expectEqual(@as(u8, 0x63), lanes[0]);
    try std.testing.expectEqual(@as(u8, 0x63), lanes[16]);
}

test "CLEO computes square roots lane-wise" {
    const src = fromArray(256, f32, .{ 4, 9, 16, 25, 36, 49, 64, 81 });
    const out = mapUnary(256, f32, src, .sqrt);
    try std.testing.expectEqual([_]f32{ 2, 3, 4, 5, 6, 7, 8, 9 }, toArray(256, f32, out));
}

test "CLEO shuffles packed double lanes and applies AVX512 masks" {
    const merge = fromArray(512, u64, .{ 100, 101, 102, 103, 104, 105, 106, 107 });
    const lhs = fromArray(512, u64, .{ 1, 2, 3, 4, 5, 6, 7, 8 });
    const rhs = fromArray(512, u64, .{ 10, 20, 30, 40, 50, 60, 70, 80 });
    const out = shuffleImmediatePDMasked(512, merge, lhs, rhs, 0b10_01_10_01, 0b01010101, .merge);
    try std.testing.expectEqual([_]u64{ 2, 101, 3, 103, 6, 105, 7, 107 }, toArray(512, u64, out));
}
