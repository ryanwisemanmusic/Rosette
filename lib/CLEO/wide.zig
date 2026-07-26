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

pub const ConvertOp = enum {
    f64_to_f32,
    f32_to_f64,
    s32_to_f32,
    f32_to_s32,
    f32_to_s32_trunc,
};

pub const PackOp = enum {
    signed_saturate,
    unsigned_saturate,
};

pub const ShiftOp = enum {
    shift_left,
    shift_right_arith,
    shift_right_logical,
};

pub const DownConvertMode = enum {
    trunc,
    signed_saturate,
    unsigned_saturate,
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

pub fn broadcast(comptime bits: usize, comptime T: type, scalar: T) Wide(bits) {
    const lanes = comptime laneCount(bits, T);
    const arr: [lanes]T = [_]T{scalar} ** lanes;
    return fromArray(bits, T, arr);
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

// ──── CONVERT operations ─────────────────────────────────────────────────

/// Convert f64 lanes to f32 lanes (CVTPD2PS).  Halves the lane count;
/// the total width stays the same (e.g. 256-bit: 4×f64 → 8×f32).
pub fn cvtF64ToF32(comptime bits: usize, src: Wide(bits)) Wide(bits) {
    const out_lanes = comptime laneCount(bits, f32);
    const in_arr = toArray(bits, f64, src);
    var out_arr: [out_lanes]f32 = undefined;
    for (0..out_lanes) |lane| {
        out_arr[lane] = @floatCast(in_arr[lane / 2]);
    }
    return fromArray(bits, f32, out_arr);
}

/// Convert f32 lanes to f64 lanes (CVTPS2PD).  Doubles the lane count;
/// the total width stays the same (e.g. 256-bit: 8×f32 → 4×f64).
pub fn cvtF32ToF64(comptime bits: usize, src: Wide(bits)) Wide(bits) {
    const out_lanes = comptime laneCount(bits, f64);
    const in_arr = toArray(bits, f32, src);
    var out_arr: [out_lanes]f64 = undefined;
    for (0..out_lanes) |lane| {
        out_arr[lane] = @floatCast(in_arr[lane * 2]);
    }
    return fromArray(bits, f64, out_arr);
}

/// Convert i32 lanes to f32 lanes (CVTDQ2PS).
pub fn cvtS32ToF32(comptime bits: usize, src: Wide(bits)) Wide(bits) {
    const lanes = comptime laneCount(bits, i32);
    const in_arr = toArray(bits, i32, src);
    var out_arr: [lanes]f32 = undefined;
    for (0..lanes) |lane| out_arr[lane] = @floatFromInt(in_arr[lane]);
    return fromArray(bits, f32, out_arr);
}

/// Convert f32 lanes to i32 lanes, rounding to nearest even (CVTPS2DQ).
pub fn cvtF32ToS32(comptime bits: usize, src: Wide(bits)) Wide(bits) {
    const lanes = comptime laneCount(bits, f32);
    const in_arr = toArray(bits, f32, src);
    var out_arr: [lanes]i32 = undefined;
    for (0..lanes) |lane| out_arr[lane] = @intFromFloat(std.math.round(in_arr[lane]));
    return fromArray(bits, i32, out_arr);
}

/// Convert f32 lanes to i32 lanes, truncating toward zero (CVTTPS2DQ).
pub fn cvtF32ToS32Trunc(comptime bits: usize, src: Wide(bits)) Wide(bits) {
    const lanes = comptime laneCount(bits, f32);
    const in_arr = toArray(bits, f32, src);
    var out_arr: [lanes]i32 = undefined;
    for (0..lanes) |lane| out_arr[lane] = @intFromFloat(in_arr[lane]);
    return fromArray(bits, i32, out_arr);
}

// ──── SHIFT operations ──────────────────────────────────────────────────

/// Shift each lane left by `count` bits (PSLL).
pub fn shiftLeft(comptime bits: usize, comptime T: type, src: Wide(bits), count: u64) Wide(bits) {
    const lanes = comptime laneCount(bits, T);
    const in_arr = toArray(bits, T, src);
    var out_arr: [lanes]T = undefined;
    for (0..lanes) |lane| out_arr[lane] = in_arr[lane] << @intCast(count % @bitSizeOf(T));
    return fromArray(bits, T, out_arr);
}

/// Shift each lane right arithmetically by `count` bits (PSRA).
pub fn shiftRightArith(comptime bits: usize, comptime T: type, src: Wide(bits), count: u64) Wide(bits) {
    const lanes = comptime laneCount(bits, T);
    const in_arr = toArray(bits, T, src);
    var out_arr: [lanes]T = undefined;
    for (0..lanes) |lane| out_arr[lane] = in_arr[lane] >> @intCast(count % @bitSizeOf(T));
    return fromArray(bits, T, out_arr);
}

/// Shift each lane right logically by `count` bits (PSRL).
pub fn shiftRightLog(comptime bits: usize, comptime T: type, src: Wide(bits), count: u64) Wide(bits) {
    const lanes = comptime laneCount(bits, T);
    const UT = std.meta.Int(.unsigned, @bitSizeOf(T));
    const in_arr = toArray(bits, UT, src);
    var out_arr: [lanes]UT = undefined;
    for (0..lanes) |lane| out_arr[lane] = in_arr[lane] >> @intCast(count % @bitSizeOf(UT));
    return fromArray(bits, UT, out_arr);
}

/// Shift each lane left by a lane-specific count from `counts` (VPSLLV).
pub fn shiftLeftVariable(comptime bits: usize, comptime T: type, src: Wide(bits), counts: Wide(bits)) Wide(bits) {
    const lanes = comptime laneCount(bits, T);
    const in_arr = toArray(bits, T, src);
    const cnt_arr = toArray(bits, T, counts);
    var out_arr: [lanes]T = undefined;
    for (0..lanes) |lane| out_arr[lane] = in_arr[lane] << @intCast(@as(u64, @intCast(cnt_arr[lane])) % @bitSizeOf(T));
    return fromArray(bits, T, out_arr);
}

/// Shift each lane right arithmetically by a lane-specific count (VPSRAV).
pub fn shiftRightArithVariable(comptime bits: usize, comptime T: type, src: Wide(bits), counts: Wide(bits)) Wide(bits) {
    const lanes = comptime laneCount(bits, T);
    const in_arr = toArray(bits, T, src);
    const cnt_arr = toArray(bits, T, counts);
    var out_arr: [lanes]T = undefined;
    for (0..lanes) |lane| out_arr[lane] = in_arr[lane] >> @intCast(@as(u64, @intCast(cnt_arr[lane])) % @bitSizeOf(T));
    return fromArray(bits, T, out_arr);
}

/// Shift each lane right logically by a lane-specific count (VPSRLV).
pub fn shiftRightLogVariable(comptime bits: usize, comptime T: type, src: Wide(bits), counts: Wide(bits)) Wide(bits) {
    const lanes = comptime laneCount(bits, T);
    const UT = std.meta.Int(.unsigned, @bitSizeOf(T));
    const in_arr = toArray(bits, UT, src);
    const cnt_arr = toArray(bits, UT, counts);
    var out_arr: [lanes]UT = undefined;
    for (0..lanes) |lane| out_arr[lane] = in_arr[lane] >> @intCast(@as(u64, @intCast(cnt_arr[lane])) % @bitSizeOf(UT));
    return fromArray(bits, UT, out_arr);
}

// ──── PACK operations ────────────────────────────────────────────────────

/// Pack two source vectors of wider elements into one vector of narrower
/// elements using signed saturation (PACKSS).
/// `lhs` fills the first half of the output, `rhs` fills the second half.
pub fn packSigned(comptime bits: usize, comptime T: type, lhs: Wide(bits), rhs: Wide(bits)) Wide(bits) {
    const NarrowT = std.meta.Int(.signed, @bitSizeOf(T) / 2);
    const out_lanes = comptime laneCount(bits, NarrowT);
    const a = toArray(bits, T, lhs);
    const b = toArray(bits, T, rhs);
    var out_arr: [out_lanes]NarrowT = undefined;
    const block_lanes = comptime 128 / @bitSizeOf(T);
    const blocks = comptime bits / 128;
    for (0..blocks) |block| {
        const blk = block * block_lanes;
        const oblk = block * block_lanes * 2;
        for (0..block_lanes) |lane| {
            out_arr[oblk + lane] = std.math.cast(NarrowT, a[blk + lane]) orelse
                if (a[blk + lane] < 0) std.math.minInt(NarrowT) else std.math.maxInt(NarrowT);
            out_arr[oblk + block_lanes + lane] = std.math.cast(NarrowT, b[blk + lane]) orelse
                if (b[blk + lane] < 0) std.math.minInt(NarrowT) else std.math.maxInt(NarrowT);
        }
    }
    return fromArray(bits, NarrowT, out_arr);
}

/// Pack two source vectors of wider elements into one vector of narrower
/// elements using unsigned saturation (PACKUS).
/// `lhs` fills the first half of the output, `rhs` fills the second half.
pub fn packUnsigned(comptime bits: usize, comptime T: type, lhs: Wide(bits), rhs: Wide(bits)) Wide(bits) {
    const NarrowU = std.meta.Int(.unsigned, @bitSizeOf(T) / 2);
    const out_lanes = comptime laneCount(bits, NarrowU);
    const a = toArray(bits, T, lhs);
    const b = toArray(bits, T, rhs);
    var out_arr: [out_lanes]NarrowU = undefined;
    const SignedT = std.meta.Int(.signed, @bitSizeOf(T));
    const block_lanes = comptime 128 / @bitSizeOf(T);
    const blocks = comptime bits / 128;
    for (0..blocks) |block| {
        const blk = block * block_lanes;
        const oblk = block * block_lanes * 2;
        for (0..block_lanes) |lane| {
            out_arr[oblk + lane] = std.math.cast(NarrowU, @as(SignedT, @intCast(a[blk + lane]))) orelse std.math.maxInt(NarrowU);
            out_arr[oblk + block_lanes + lane] = std.math.cast(NarrowU, @as(SignedT, @intCast(b[blk + lane]))) orelse std.math.maxInt(NarrowU);
        }
    }
    return fromArray(bits, NarrowU, out_arr);
}

pub fn duplicateLowF64Per128(comptime bits: usize, value: Wide(bits)) Wide(bits) {
    const lanes = comptime laneCount(bits, u64);
    const src = toArray(bits, u64, value);
    var out: [lanes]u64 = undefined;
    for (0..lanes) |lane| out[lane] = src[(lane / 2) * 2];
    return fromArray(bits, u64, out);
}

// ──── MOV operations (partial register moves) ──────────────────────────

/// Copy upper 64 bits of src to lower 64 bits of dest, preserving dest[127:64].
pub fn moveHighToLow(comptime bits: usize, dest: Wide(bits), src: Wide(bits)) Wide(bits) {
    var result = dest;
    if (bits >= 128) {
        @memcpy(result.bytes[0..8], src.bytes[8..16]);
    }
    return result;
}

/// Copy lower 64 bits of src to upper 64 bits of dest, preserving dest[63:0].
pub fn moveLowToHigh(comptime bits: usize, dest: Wide(bits), src: Wide(bits)) Wide(bits) {
    var result = dest;
    if (bits >= 128) {
        @memcpy(result.bytes[8..16], src.bytes[0..8]);
    }
    return result;
}

// ──── P1 operations: ABSOLUTE value, SIGN negation, bitwise NOT ────────

/// Absolute value of each signed lane (PABS).
pub fn absValue(comptime bits: usize, comptime T: type, src: Wide(bits)) Wide(bits) {
    const lanes = comptime laneCount(bits, T);
    const in_arr = toArray(bits, T, src);
    var out_arr: [lanes]T = undefined;
    for (0..lanes) |lane| {
        out_arr[lane] = if (in_arr[lane] < 0) -in_arr[lane] else in_arr[lane];
    }
    return fromArray(bits, T, out_arr);
}

/// Signed negation based on sign of second operand (PSIGN).
/// For each lane: rhs<0 → -lhs, rhs==0 → 0, else → lhs.
pub fn signOperation(comptime bits: usize, comptime T: type, lhs: Wide(bits), rhs: Wide(bits)) Wide(bits) {
    const lanes = comptime laneCount(bits, T);
    const a = toArray(bits, T, lhs);
    const b = toArray(bits, T, rhs);
    var out_arr: [lanes]T = undefined;
    for (0..lanes) |lane| {
        out_arr[lane] = if (b[lane] < 0) -a[lane] else if (b[lane] == 0) @as(T, 0) else a[lane];
    }
    return fromArray(bits, T, out_arr);
}

/// Bitwise NOT of each lane (PNOT).
pub fn bitwiseNot(comptime bits: usize, comptime T: type, src: Wide(bits)) Wide(bits) {
    const lanes = comptime laneCount(bits, T);
    const in_arr = toArray(bits, T, src);
    var out_arr: [lanes]T = undefined;
    for (0..lanes) |lane| out_arr[lane] = ~in_arr[lane];
    return fromArray(bits, T, out_arr);
}

// ──── P2 operations: DOWN-CONVERT (element narrowing) ──────────────────

/// Down-convert wider elements to narrower elements packed into the low
/// portion of the output.  The upper bytes are zeroed.
/// `InT` is the input element type (e.g. u32 for VPMOVDB), `OutT` is the
/// output element type (e.g. u8 for VPMOVDB).
pub fn downConvert(comptime bits: usize, comptime InT: type, comptime OutT: type, src: Wide(bits), comptime mode: DownConvertMode) Wide(bits) {
    const in_lanes = comptime laneCount(bits, InT);
    const out_total_lanes = comptime laneCount(bits, OutT);
    const in_arr = toArray(bits, InT, src);
    var out_arr: [out_total_lanes]OutT = [_]OutT{0} ** out_total_lanes;
    switch (mode) {
        .trunc => for (0..in_lanes) |lane| {
            out_arr[lane] = @as(OutT, @truncate(in_arr[lane]));
        },
        .signed_saturate => for (0..in_lanes) |lane| {
            const SignedInT = std.meta.Int(.signed, @bitSizeOf(InT));
            const SignedOutT = std.meta.Int(.signed, @bitSizeOf(OutT));
            const as_signed = @as(SignedInT, @bitCast(in_arr[lane]));
            const sat: SignedOutT = std.math.cast(SignedOutT, as_signed) orelse
                (if (as_signed < 0) std.math.minInt(SignedOutT) else std.math.maxInt(SignedOutT));
            out_arr[lane] = @as(OutT, @bitCast(sat));
        },
        .unsigned_saturate => for (0..in_lanes) |lane| {
            const SignedOutT = std.meta.Int(.signed, @bitSizeOf(OutT));
            const as_signed = @as(std.meta.Int(.signed, @bitSizeOf(InT)), @bitCast(in_arr[lane]));
            const clipped: SignedOutT = std.math.cast(SignedOutT, as_signed) orelse
                (if (as_signed < 0) @as(SignedOutT, 0) else std.math.maxInt(SignedOutT));
            out_arr[lane] = @as(OutT, @bitCast(clipped));
        },
    }
    return fromArray(bits, OutT, out_arr);
}

// ──── P1 operations: BROADCAST lane and BLOCK INSERT ──────────────────

/// Broadcast the first lane element across all lanes (VBROADCAST*).
pub fn broadcastLane(comptime bits: usize, comptime T: type, src: Wide(bits)) Wide(bits) {
    const arr = toArray(bits, T, src);
    return broadcast(bits, T, arr[0]);
}

/// Insert a 128-bit block from `src` into `dest` at the position selected by
/// `block_index` (VINSERTF128/I128/F32x4/I32x4, etc.).
/// Each 128-bit block is independently replaceable.
pub fn insertBlock(comptime bits: usize, dest: Wide(bits), src: Wide(bits), block_index: usize) Wide(bits) {
    const block_bytes = 128 / 8;
    const blocks = comptime bits / 128;
    var result = dest;
    if (block_index < blocks) {
        const offset = block_index * block_bytes;
        @memcpy(result.bytes[offset..][0..block_bytes], src.bytes[offset..][0..block_bytes]);
    }
    return result;
}

// ──── P3 operations: ALIGN (vector element alignment) ──────────────────

/// Align two source vectors by concatenating `rhs` (high half) and `lhs`
/// (low half), then extracting a contiguous result starting at byte offset
/// `imm * element_bytes`.  (VALIGND / VALIGNQ semantics.)
pub fn @"align"(comptime bits: usize, comptime T: type, lhs: Wide(bits), rhs: Wide(bits), imm: u8) Wide(bits) {
    const lanes = comptime laneCount(bits, T);
    const concat_lanes = comptime lanes * 2; // concatenated [rhs | lhs]
    const a = toArray(bits, T, lhs);
    const b = toArray(bits, T, rhs);
    // Concatenate b[0..lanes] (rhs) then a[0..lanes] (lhs)
    var concat: [concat_lanes]T = undefined;
    for (0..lanes) |i| concat[i] = b[i];
    for (0..lanes) |i| concat[lanes + i] = a[i];
    // Extract starting at lane `imm` modulo concat_lanes, wrapping around
    var out: [lanes]T = undefined;
    const start_lane = @as(usize, imm) % concat_lanes;
    for (0..lanes) |i| out[i] = concat[(start_lane + i) % concat_lanes];
    return fromArray(bits, T, out);
}

// ──── P3 operations: AVERAGE (unsigned element average) ─────────────────

/// Unsigned average of two byte/word vectors: (a + b + 1) >> 1 (PAVGB/PAVGW).
pub fn average(comptime bits: usize, comptime T: type, lhs: Wide(bits), rhs: Wide(bits)) Wide(bits) {
    const lanes = comptime laneCount(bits, T);
    const a = toArray(bits, T, lhs);
    const b = toArray(bits, T, rhs);
    var out: [lanes]T = undefined;
    for (0..lanes) |lane| out[lane] = @truncate((@as(u64, a[lane]) + @as(u64, b[lane]) + 1) >> 1);
    return fromArray(bits, T, out);
}

// ──── P3 operations: ROTATE (element rotation) ─────────────────────────

/// Rotate each element left by `count` bits (VPROLD / VPROLQ).
pub fn rotateLeft(comptime bits: usize, comptime T: type, src: Wide(bits), count: u64) Wide(bits) {
    const lanes = comptime laneCount(bits, T);
    const in_arr = toArray(bits, T, src);
    const elem_bits = comptime @bitSizeOf(T);
    const ShiftAmt = comptime if (elem_bits <= 32) u5 else u6;
    const UT = std.meta.Int(.unsigned, elem_bits);
    const mask64: u64 = comptime @intCast(elem_bits - 1);
    var out_arr: [lanes]T = undefined;
    for (0..lanes) |lane| {
        const r: ShiftAmt = @truncate(count & mask64);
        const val: UT = @bitCast(in_arr[lane]);
        out_arr[lane] = if (r == 0)
            @bitCast(val)
        else
            @bitCast((val << r) | (val >> @as(ShiftAmt, @truncate(elem_bits - @as(usize, r)))));
    }
    return fromArray(bits, T, out_arr);
}

/// Rotate each element right by `count` bits (VPRORD / VPRORQ).
pub fn rotateRight(comptime bits: usize, comptime T: type, src: Wide(bits), count: u64) Wide(bits) {
    const lanes = comptime laneCount(bits, T);
    const in_arr = toArray(bits, T, src);
    const elem_bits = comptime @bitSizeOf(T);
    const ShiftAmt = comptime if (elem_bits <= 32) u5 else u6;
    const UT = std.meta.Int(.unsigned, elem_bits);
    const mask64: u64 = comptime @intCast(elem_bits - 1);
    var out_arr: [lanes]T = undefined;
    for (0..lanes) |lane| {
        const r: ShiftAmt = @truncate(count & mask64);
        const val: UT = @bitCast(in_arr[lane]);
        out_arr[lane] = if (r == 0)
            @bitCast(val)
        else
            @bitCast((val >> r) | (val << @as(ShiftAmt, @truncate(elem_bits - @as(usize, r)))));
    }
    return fromArray(bits, T, out_arr);
}

/// Rotate each element left by a lane-specific count from `counts` (VPROLVD / VPROLVQ).
pub fn rotateLeftVariable(comptime bits: usize, comptime T: type, src: Wide(bits), counts: Wide(bits)) Wide(bits) {
    const lanes = comptime laneCount(bits, T);
    const in_arr = toArray(bits, T, src);
    const cnt_arr = toArray(bits, T, counts);
    const elem_bits = comptime @bitSizeOf(T);
    const ShiftAmt = comptime if (elem_bits <= 32) u5 else u6;
    const UT = std.meta.Int(.unsigned, elem_bits);
    const mask64: u64 = comptime @intCast(elem_bits - 1);
    var out_arr: [lanes]T = undefined;
    for (0..lanes) |lane| {
        // Reinterpret signed count bits as unsigned, then extract low bits as rotation amount.
        // This matches x86 semantics: the count is the unsigned value of the low element bits.
        const cnt_u64: u64 = @as(u64, @as(UT, @bitCast(cnt_arr[lane])));
        const r: ShiftAmt = @truncate(cnt_u64 & mask64);
        const val: UT = @bitCast(in_arr[lane]);
        out_arr[lane] = if (r == 0)
            @bitCast(val)
        else
            @bitCast((val << r) | (val >> @as(ShiftAmt, @truncate(elem_bits - @as(usize, r)))));
    }
    return fromArray(bits, T, out_arr);
}

/// Rotate each element right by a lane-specific count from `counts` (VPRORVD / VPRORVQ).
pub fn rotateRightVariable(comptime bits: usize, comptime T: type, src: Wide(bits), counts: Wide(bits)) Wide(bits) {
    const lanes = comptime laneCount(bits, T);
    const in_arr = toArray(bits, T, src);
    const cnt_arr = toArray(bits, T, counts);
    const elem_bits = comptime @bitSizeOf(T);
    const ShiftAmt = comptime if (elem_bits <= 32) u5 else u6;
    const UT = std.meta.Int(.unsigned, elem_bits);
    const mask64: u64 = comptime @intCast(elem_bits - 1);
    var out_arr: [lanes]T = undefined;
    for (0..lanes) |lane| {
        // Reinterpret signed count bits as unsigned.
        const cnt_u64: u64 = @as(u64, @as(UT, @bitCast(cnt_arr[lane])));
        const r: ShiftAmt = @truncate(cnt_u64 & mask64);
        const val: UT = @bitCast(in_arr[lane]);
        out_arr[lane] = if (r == 0)
            @bitCast(val)
        else
            @bitCast((val >> r) | (val << @as(ShiftAmt, @truncate(elem_bits - @as(usize, r)))));
    }
    return fromArray(bits, T, out_arr);
}

// ──── P3 operations: TERNARY LOGIC (bitwise three-operand) ────────────

/// Bitwise ternary logic (VPTERNLOG).  For each bit, the result is
/// determined by the truth table encoded in `imm`:
///   result_bit = (imm >> ((c_bit << 2) | (b_bit << 1) | a_bit)) & 1
pub fn ternaryLogic(comptime bits: usize, comptime T: type, lhs: Wide(bits), rhs: Wide(bits), imm: u8) Wide(bits) {
    const lanes = comptime laneCount(bits, T);
    const a = toArray(bits, T, lhs);
    const b = toArray(bits, T, rhs);
    var out_arr: [lanes]T = undefined;
    const bit_count = comptime @bitSizeOf(T);
    for (0..lanes) |lane| {
        const av = a[lane];
        const bv = b[lane];
        var result: T = 0;
        var bit: usize = 0;
        while (bit < bit_count) : (bit += 1) {
            const a_bit: u3 = @truncate((@as(std.meta.Int(.unsigned, bit_count), @intCast(av)) >> @intCast(bit)) & 1);
            const b_bit: u3 = @truncate((@as(std.meta.Int(.unsigned, bit_count), @intCast(bv)) >> @intCast(bit)) & 1);
            const k = (b_bit << 1) | a_bit;
            const out_bit = (imm >> k) & 1;
            if (out_bit == 1) result |= @as(T, 1) << @intCast(bit);
        }
        out_arr[lane] = result;
    }
    return fromArray(bits, T, out_arr);
}

// ──── P3 operations: GALOIS FIELD (GF2P8) ────────────────────────────

/// Multiply two bytes in GF(2^8) using polynomial 0x11B.
fn gf2p8MulByte(a: u8, b: u8) u8 {
    var x = a;
    var y = b;
    var result: u8 = 0;
    for (0..8) |_| {
        if ((y & 1) != 0) result ^= x;
        const hi = (x & 0x80) != 0;
        x <<= 1;
        if (hi) x ^= 0x1B;
        y >>= 1;
    }
    return result;
}

/// GF(2^8) multiplicative inverse (table via exponentiation).
fn gf2p8InvByte(x: u8) u8 {
    if (x == 0) return 0;
    var result = x;
    for (0..6) |_| {
        result = gf2p8MulByte(result, result);
        result = gf2p8MulByte(result, x);
    }
    return result;
}

/// Multiply bytes in GF(2^8) (GF2P8MULB).
pub fn gf2p8Mul(comptime bits: usize, lhs: Wide(bits), rhs: Wide(bits)) Wide(bits) {
    const lanes = comptime laneCount(bits, u8);
    const a = toArray(bits, u8, lhs);
    const b = toArray(bits, u8, rhs);
    var out_arr: [lanes]u8 = undefined;
    for (0..lanes) |lane| out_arr[lane] = gf2p8MulByte(a[lane], b[lane]);
    return fromArray(bits, u8, out_arr);
}

/// GF(2^8) affine transform with 8-bit immediate (GF2P8AFFINEQB).
pub fn gf2p8Affine(comptime bits: usize, lhs: Wide(bits), rhs: Wide(bits), imm: u8) Wide(bits) {
    const lanes = comptime laneCount(bits, u8);
    const a = toArray(bits, u8, lhs);
    const b = toArray(bits, u8, rhs);
    var out_arr: [lanes]u8 = undefined;
    for (0..lanes) |lane| {
        out_arr[lane] = gf2p8MulByte(a[lane], b[lane]) ^ imm;
    }
    return fromArray(bits, u8, out_arr);
}

/// GF(2^8) inverse + affine transform (GF2P8AFFINEINVQB).
pub fn gf2p8AffineInv(comptime bits: usize, lhs: Wide(bits), rhs: Wide(bits), imm: u8) Wide(bits) {
    const lanes = comptime laneCount(bits, u8);
    const a = toArray(bits, u8, lhs);
    const b = toArray(bits, u8, rhs);
    var out_arr: [lanes]u8 = undefined;
    for (0..lanes) |lane| {
        const inv = gf2p8InvByte(a[lane]);
        out_arr[lane] = gf2p8MulByte(inv, b[lane]) ^ imm;
    }
    return fromArray(bits, u8, out_arr);
}

// ──── P3 operations: ROUND to integer ────────────────────────────────

/// Round each float element to the nearest integer value (FRNDINT-like).
pub fn roundToInt(comptime bits: usize, comptime T: type, src: Wide(bits)) Wide(bits) {
    const lanes = comptime laneCount(bits, T);
    const in_arr = toArray(bits, T, src);
    var out_arr: [lanes]T = undefined;
    for (0..lanes) |lane| out_arr[lane] = std.math.round(in_arr[lane]);
    return fromArray(bits, T, out_arr);
}

// ──── P3 operations: SHA (SHA1 / SHA256) ─────────────────────────────

/// SHA1 message schedule update (SHA1MSG1): src1 ^ ROL(src2, 1) per-lane.
pub fn sha1Msg1(comptime bits: usize, lhs: Wide(bits), rhs: Wide(bits)) Wide(bits) {
    const lanes = comptime laneCount(bits, u32);
    const a = toArray(bits, u32, lhs);
    const b = toArray(bits, u32, rhs);
    var out_arr: [lanes]u32 = undefined;
    for (0..lanes) |lane| out_arr[lane] = a[lane] ^ std.math.rotl(u32, b[lane], 1);
    return fromArray(bits, u32, out_arr);
}

/// SHA1 message schedule update part 2 (SHA1MSG2): ROL(src1 ^ src2, 31) per-lane.
pub fn sha1Msg2(comptime bits: usize, lhs: Wide(bits), rhs: Wide(bits)) Wide(bits) {
    const lanes = comptime laneCount(bits, u32);
    const a = toArray(bits, u32, lhs);
    const b = toArray(bits, u32, rhs);
    var out_arr: [lanes]u32 = undefined;
    for (0..lanes) |lane| out_arr[lane] = std.math.rotl(u32, a[lane] ^ b[lane], 31);
    return fromArray(bits, u32, out_arr);
}

/// SHA1 next round key (SHA1NEXTE): src1 + ROL(src2, 30) per-lane.
pub fn sha1Nexte(comptime bits: usize, lhs: Wide(bits), rhs: Wide(bits)) Wide(bits) {
    const lanes = comptime laneCount(bits, u32);
    const a = toArray(bits, u32, lhs);
    const b = toArray(bits, u32, rhs);
    var out_arr: [lanes]u32 = undefined;
    for (0..lanes) |lane| out_arr[lane] = a[lane] +% std.math.rotl(u32, b[lane], 30);
    return fromArray(bits, u32, out_arr);
}

/// SHA1 four rounds (SHA1RNDS4).  Immediate selects round constant (0-3).
pub fn sha1Rnds4(comptime bits: usize, lhs: Wide(bits), rhs: Wide(bits), imm: u8) Wide(bits) {
    const lanes = comptime laneCount(bits, u32);
    const a = toArray(bits, u32, lhs);
    const b = toArray(bits, u32, rhs);
    const k: u32 = switch (imm & 0x3) {
        0 => 0x5A827999,
        1 => 0x6ED9EBA1,
        2 => 0x8F1BBCDC,
        3 => 0xCA62C1D6,
        else => unreachable,
    };
    var out_arr: [lanes]u32 = undefined;
    for (0..lanes) |lane| {
        const ch = (a[lane] & b[lane]) ^ (~a[lane] & k);
        out_arr[lane] = std.math.rotl(u32, a[lane], 5) +% ch +% k;
    }
    return fromArray(bits, u32, out_arr);
}

/// SHA256 message schedule update (SHA256MSG1).
pub fn sha256Msg1(comptime bits: usize, lhs: Wide(bits), rhs: Wide(bits)) Wide(bits) {
    const lanes = comptime laneCount(bits, u32);
    const a = toArray(bits, u32, lhs);
    const b = toArray(bits, u32, rhs);
    var out_arr: [lanes]u32 = undefined;
    for (0..lanes) |lane| {
        const t = b[lane];
        const sigma0 = std.math.rotl(u32, t, 7) ^ std.math.rotl(u32, t, 18) ^ (t >> 3);
        out_arr[lane] = a[lane] +% sigma0;
    }
    return fromArray(bits, u32, out_arr);
}

/// SHA256 message schedule update part 2 (SHA256MSG2).
pub fn sha256Msg2(comptime bits: usize, lhs: Wide(bits), rhs: Wide(bits)) Wide(bits) {
    const lanes = comptime laneCount(bits, u32);
    const a = toArray(bits, u32, lhs);
    const b = toArray(bits, u32, rhs);
    var out_arr: [lanes]u32 = undefined;
    for (0..lanes) |lane| {
        const s1 = std.math.rotl(u32, a[lane], 7) ^ std.math.rotl(u32, a[lane], 18) ^ (a[lane] >> 3);
        const s2 = std.math.rotl(u32, b[lane], 17) ^ std.math.rotl(u32, b[lane], 19) ^ (b[lane] >> 10);
        out_arr[lane] = s1 +% s2;
    }
    return fromArray(bits, u32, out_arr);
}

/// SHA256 two rounds (SHA256RNDS2).
pub fn sha256Rnds2(comptime bits: usize, lhs: Wide(bits), rhs: Wide(bits)) Wide(bits) {
    const lanes = comptime laneCount(bits, u32);
    const a = toArray(bits, u32, lhs);
    const b = toArray(bits, u32, rhs);
    var out_arr: [lanes]u32 = undefined;
    for (0..lanes) |lane| {
        const sigma1 = std.math.rotl(u32, a[lane], 6) ^ std.math.rotl(u32, a[lane], 11) ^ std.math.rotl(u32, a[lane], 25);
        out_arr[lane] = b[lane] +% sigma1;
    }
    return fromArray(bits, u32, out_arr);
}

// ──── P3 operations: TWO-SOURCE PERMUTE (VPERMI2 / VPERMT2) ──────────

/// Two-source permute using index vector (VPERMI2* / VPERMT2*).
/// For each element position i, selects from `src2` or `src3` based on
/// the index value in the corresponding lane of `index_vector`.
pub fn twoSourcePermute(comptime bits: usize, comptime T: type, index_vector: Wide(bits), src2: Wide(bits), src3: Wide(bits)) Wide(bits) {
    const lanes = comptime laneCount(bits, T);
    const idx = toArray(bits, T, index_vector);
    const s2 = toArray(bits, T, src2);
    const s3 = toArray(bits, T, src3);
    var out_arr: [lanes]T = undefined;
    for (0..lanes) |lane| {
        const sel_raw = @as(usize, @intCast(idx[lane]));
        if (sel_raw < lanes) {
            out_arr[lane] = s2[sel_raw];
        } else {
            out_arr[lane] = s3[sel_raw -% lanes];
        }
    }
    return fromArray(bits, T, out_arr);
}

// ──── P4 operations: SCALE (VSCALEF) ──────────────────────────────────

/// Scale each float lane: result = lhs * 2^floor(rhs) (VSCALEFPS/VSCALEFPD).
pub fn scaleFloat(comptime bits: usize, comptime T: type, lhs: Wide(bits), rhs: Wide(bits)) Wide(bits) {
    const lanes = comptime laneCount(bits, T);
    const a = toArray(bits, T, lhs);
    const b = toArray(bits, T, rhs);
    var out_arr: [lanes]T = undefined;
    for (0..lanes) |lane| {
        const exponent = @as(i32, @intFromFloat(std.math.floor(b[lane])));
        out_arr[lane] = a[lane] * std.math.ldexp(@as(T, 1.0), exponent);
    }
    return fromArray(bits, T, out_arr);
}

// ──── P4 operations: RANGE (min/max with immediate) ─────────────────────

/// Range operation with immediate selector (VRANGEPS/VRANGEPD).
/// imm[2:0]: 0=min, 1=max, 2=minabs, 3=maxabs
pub fn rangeFloat(comptime bits: usize, comptime T: type, lhs: Wide(bits), rhs: Wide(bits), imm: u8) Wide(bits) {
    const lanes = comptime laneCount(bits, T);
    const a = toArray(bits, T, lhs);
    const b = toArray(bits, T, rhs);
    var out_arr: [lanes]T = undefined;
    for (0..lanes) |lane| {
        out_arr[lane] = switch (imm & 0x7) {
            0 => @min(a[lane], b[lane]),
            1 => @max(a[lane], b[lane]),
            2 => @min(@abs(a[lane]), @abs(b[lane])),
            3 => @max(@abs(a[lane]), @abs(b[lane])),
            else => @min(a[lane], b[lane]), // default to min
        };
    }
    return fromArray(bits, T, out_arr);
}

// ──── P4 operations: FIXUP (VFIXUPIMM) ────────────────────────────────

/// Fixup special float values with immediate table (VFIXUPIMMPS/VFIXUPIMMPD).
/// Simplified: for normal numbers returns lhs; for NaN uses imm selectors.
pub fn fixupFloat(comptime bits: usize, comptime T: type, lhs: Wide(bits), rhs: Wide(bits), imm: u8) Wide(bits) {
    const lanes = comptime laneCount(bits, T);
    const a = toArray(bits, T, lhs);
    const b = toArray(bits, T, rhs);
    var out_arr: [lanes]T = undefined;
    for (0..lanes) |lane| {
        if (std.math.isNan(b[lane])) {
            // Use immediate to decide NaN behavior (simplified)
            out_arr[lane] = if ((imm & 0x01) != 0) a[lane] else @as(T, 0);
        } else if (std.math.isInf(b[lane])) {
            out_arr[lane] = if (b[lane] > 0) a[lane] else -a[lane];
        } else {
            out_arr[lane] = a[lane]; // normal: passthrough
        }
    }
    return fromArray(bits, T, out_arr);
}

// ──── P4 operations: COMPRESS — identity for now ───────────────────────

/// Compress float elements using mask (VCOMPRESSPD/VCOMPRESSPS).
/// Simplified: identity operation (returns source unchanged).
/// Full implementation requires mask-aware compaction.
pub fn compressFloat(comptime bits: usize, comptime T: type, src: Wide(bits)) Wide(bits) {
    _ = T;
    return src;
}

// ──── P4 operations: EXPAND — identity for now ────────────────────────

/// Expand float elements using mask (VEXPANDPD/VEXPANDPS).
/// Simplified: identity operation (returns source unchanged).
/// Full implementation requires mask-aware expansion.
pub fn expandFloat(comptime bits: usize, comptime T: type, src: Wide(bits)) Wide(bits) {
    _ = T;
    return src;
}

// ──── PERMUTE operations: single-source permute (VPERM) ────────────────

/// Permute dword elements using an index vector (VPERMD).
/// For each lane i, result[i] = src[index_vector[i] % lanes].
pub fn permuteDWord(comptime bits: usize, src: Wide(bits), index_vector: Wide(bits)) Wide(bits) {
    const lanes = comptime laneCount(bits, u32);
    const s = toArray(bits, u32, src);
    const idx = toArray(bits, u32, index_vector);
    var out_arr: [lanes]u32 = undefined;
    for (0..lanes) |lane| out_arr[lane] = s[@as(usize, @intCast(idx[lane])) % lanes];
    return fromArray(bits, u32, out_arr);
}

/// Permute qword elements using an index vector (VPERMQ).
/// For each lane i, result[i] = src[index_vector[i] % lanes].
pub fn permuteQWord(comptime bits: usize, src: Wide(bits), index_vector: Wide(bits)) Wide(bits) {
    const lanes = comptime laneCount(bits, u64);
    const s = toArray(bits, u64, src);
    const idx = toArray(bits, u64, index_vector);
    var out_arr: [lanes]u64 = undefined;
    for (0..lanes) |lane| out_arr[lane] = s[@as(usize, @intCast(idx[lane])) % lanes];
    return fromArray(bits, u64, out_arr);
}

/// Permute within each 128-bit lane using an immediate (VPERMILPS/VPERMILPD).
/// For each 128-bit block of 4 f32s, imm[1:0] selects which source lane goes
/// to each output lane: 00=element0, 01=element1, 10=element2, 11=element3.
/// For f64, imm[0] selects the element for each output position.
pub fn permil(comptime bits: usize, comptime T: type, src: Wide(bits), imm: u8) Wide(bits) {
    const lanes = comptime laneCount(bits, T);
    const s = toArray(bits, T, src);
    var out_arr: [lanes]T = undefined;
    if (T == f64 or T == u64) {
        // 2 elements per 128-bit block
        const blk_lanes: usize = 2;
        const blocks = lanes / blk_lanes;
        for (0..blocks) |blk| {
            const base = blk * blk_lanes;
            const shift_a: u3 = @truncate(blk * 2 + 0);
            const shift_b: u3 = @truncate(blk * 2 + 1);
            const a_idx: usize = if ((imm >> shift_a) & 1 != 0) 1 else 0;
            const b_idx: usize = if ((imm >> shift_b) & 1 != 0) 1 else 0;
            out_arr[base + 0] = s[base + a_idx];
            out_arr[base + 1] = s[base + b_idx];
        }
    } else {
        // 4 elements per 128-bit block (f32 or u32)
        const blk_lanes: usize = 4;
        const blocks = lanes / blk_lanes;
        for (0..blocks) |blk| {
            const base = blk * blk_lanes;
            for (0..blk_lanes) |i| {
                const sel = (imm >> @intCast(i * 2)) & 0x3;
                out_arr[base + i] = s[base + @as(usize, sel)];
            }
        }
    }
    return fromArray(bits, T, out_arr);
}

// ──── INSERT operations: element insert (PINSR) ────────────────────────

/// Insert a scalar element from `src` into `dest` at lane position `lane_idx`.
/// The lane position is taken from the immediate (PINSRB/PINSRD/PINSRQ/PINSRW)
/// or from the upper bits of the selector (INSERTPS).
pub fn insertElement(comptime bits: usize, comptime T: type, dest: Wide(bits), src: Wide(bits), lane_idx: usize) Wide(bits) {
    const lanes = comptime laneCount(bits, T);
    var arr = toArray(bits, T, dest);
    const src_arr = toArray(bits, T, src);
    if (lane_idx < lanes) arr[lane_idx] = src_arr[0];
    return fromArray(bits, T, arr);
}

/// Insert a dword element (INSERTPS).  The lane is selected by imm[7:6]
/// and zero-masking is controlled by imm[3:0].
pub fn insertPS(comptime bits: usize, dest: Wide(bits), src: Wide(bits), imm: u8) Wide(bits) {
    const lanes = comptime laneCount(bits, f32);
    var arr = toArray(bits, f32, dest);
    const src_arr = toArray(bits, f32, src);
    const count_src_lane: usize = @intCast((imm >> 6) & 0x3);
    const count_dst_lane: usize = @intCast((imm >> 4) & 0x3);
    if (count_src_lane < lanes and count_dst_lane < lanes) {
        arr[count_dst_lane] = src_arr[count_src_lane];
    }
    // Zero-mask: imm[3:0] selects which destination lanes to zero
    for (0..4) |i| {
        if ((imm >> @intCast(i)) & 1 != 0 and i < lanes) arr[i] = 0;
    }
    return fromArray(bits, f32, arr);
}

// ──── SHIFT operations: byte shift within 128-bit lanes (PSLLDQ/PSRLDQ) ─

/// Shift bytes left within each 128-bit lane (PSLLDQ).
/// Bytes shifted in from the right are zero.
pub fn byteShiftLeft(comptime bits: usize, src: Wide(bits), count: u64) Wide(bits) {
    const block_bytes = 128 / 8;
    const blocks = comptime bits / 128;
    var result = Wide(bits).zero();
    const src_bytes = src.bytes;
    for (0..blocks) |blk| {
        const off = blk * block_bytes;
        const shift = @min(count, block_bytes);
        const copy_len = block_bytes - shift;
        // Copy src[off..off+copy_len] to result[off+shift..off+shift+copy_len]
        @memcpy(result.bytes[off + shift ..][0..copy_len], src_bytes[off..][0..copy_len]);
    }
    return result;
}

/// Shift bytes right within each 128-bit lane (PSRLDQ).
/// Bytes shifted in from the left are zero.
pub fn byteShiftRight(comptime bits: usize, src: Wide(bits), count: u64) Wide(bits) {
    const block_bytes = 128 / 8;
    const blocks = comptime bits / 128;
    var result = Wide(bits).zero();
    const src_bytes = src.bytes;
    for (0..blocks) |blk| {
        const off = blk * block_bytes;
        const shift = @min(count, block_bytes);
        const copy_len = block_bytes - shift;
        // Copy src[off+shift..off+shift+copy_len] to result[off..off+copy_len]
        @memcpy(result.bytes[off..][0..copy_len], src_bytes[off + shift ..][0..copy_len]);
    }
    return result;
}

// ──── CONVERT operations: additional conversions ────────────────────────

/// Convert f64 lanes to i32 lanes using rounding mode (CVTPD2DQ).
pub fn cvtPd2Dq(comptime bits: usize, src: Wide(bits)) Wide(bits) {
    const in_lanes = comptime laneCount(bits, f64);
    const out_lanes = comptime laneCount(bits, i32);
    const in_arr = toArray(bits, f64, src);
    var out_arr: [out_lanes]i32 = [_]i32{0} ** out_lanes;
    for (0..in_lanes) |lane| out_arr[lane] = @intFromFloat(std.math.round(in_arr[lane]));
    return fromArray(bits, i32, out_arr);
}

/// Convert f64 lanes to i32 lanes truncating toward zero (CVTTPD2DQ).
pub fn cvttPd2Dq(comptime bits: usize, src: Wide(bits)) Wide(bits) {
    const in_lanes = comptime laneCount(bits, f64);
    const out_lanes = comptime laneCount(bits, i32);
    const in_arr = toArray(bits, f64, src);
    var out_arr: [out_lanes]i32 = [_]i32{0} ** out_lanes;
    for (0..in_lanes) |lane| out_arr[lane] = @intFromFloat(in_arr[lane]);
    return fromArray(bits, i32, out_arr);
}

/// Convert i32 lanes to f64 lanes (CVTDQ2PD).
pub fn cvtDq2Pd(comptime bits: usize, src: Wide(bits)) Wide(bits) {
    const out_lanes = comptime laneCount(bits, f64);
    const in_arr = toArray(bits, i32, src);
    var out_arr: [out_lanes]f64 = [_]f64{0.0} ** out_lanes;
    for (0..out_lanes) |lane| out_arr[lane] = @floatFromInt(in_arr[lane]);
    return fromArray(bits, f64, out_arr);
}

/// Convert f16 storage format (in upper 16 bits of u32 lanes) to f32 (VCVTPH2PS).
pub fn cvtF16ToF32(comptime bits: usize, src: Wide(bits)) Wide(bits) {
    const lanes = comptime laneCount(bits, u32);
    const in_arr = toArray(bits, u32, src);
    var out_arr: [lanes]f32 = undefined;
    for (0..lanes) |lane| {
        const f16_bits = @as(u16, @truncate(in_arr[lane] >> 16));
        // Manual f16-to-f32 conversion
        const sign = (f16_bits >> 15) & 0x1;
        const exp = (f16_bits >> 10) & 0x1F;
        const mant = f16_bits & 0x3FF;
        const f32_val: f32 = if (exp == 0) blk: {
            // Denormal or zero: (s)(0)(mant) * 2^(-14)
            const exp32: i32 = -14 - 10; // denormal exponent
            const full_mant: f32 = @floatFromInt(mant);
            const result = full_mant * std.math.ldexp(@as(f32, 1.0), exp32);
            break :blk if (sign != 0) -result else result;
        } else if (exp == 31) blk: {
            // Infinity or NaN
            break :blk if (mant == 0) std.math.inf(f32) else std.math.nan(f32);
        } else blk: {
            // Normal: (s)(exp-15)(1.mant)
            const exp32: i32 = @as(i32, exp) - 15;
            const full_mant: f32 = 1.0 + @as(f32, @floatFromInt(mant)) / 1024.0;
            const result = full_mant * std.math.ldexp(@as(f32, 1.0), exp32);
            break :blk if (sign != 0) -result else result;
        };
        out_arr[lane] = f32_val;
    }
    return fromArray(bits, f32, out_arr);
}

/// Convert f32 lanes to f16 storage format in upper 16 bits of u32 (VCVTPS2PH).
pub fn cvtF32ToF16(comptime bits: usize, src: Wide(bits)) Wide(bits) {
    const lanes = comptime laneCount(bits, f32);
    const in_arr = toArray(bits, f32, src);
    var out_arr: [lanes]u32 = undefined;
    for (0..lanes) |lane| {
        const f = in_arr[lane];
        if (std.math.isNan(f)) {
            out_arr[lane] = @as(u32, 0x7E00) << 16; // NaN
        } else if (std.math.isInf(f)) {
            const s = if (f < 0) @as(u16, 0x8000) else @as(u16, 0x0000);
            out_arr[lane] = @as(u32, s | 0x7C00) << 16;
        } else if (f == 0) {
            out_arr[lane] = 0;
        } else {
            // Naive f32-to-f16 via rounding
            const bits32 = @as(u32, @bitCast(f));
            const sign = (bits32 >> 16) & 0x8000;
            const exp = ((bits32 >> 23) & 0xFF);
            const mant = bits32 & 0x7FFFFF;
            if (exp > 0x8E) {
                // Overflow to infinity
                out_arr[lane] = @as(u32, sign | 0x7C00) << 16;
            } else if (exp < 0x71) {
                // Underflow to zero
                out_arr[lane] = @as(u32, sign) << 16;
            } else {
                const new_exp = exp - 127 + 15;
                const new_mant = mant >> 13;
                const f16_bits = @as(u16, @intCast(sign | (new_exp << 10) | new_mant));
                out_arr[lane] = @as(u32, f16_bits) << 16;
            }
        }
    }
    return fromArray(bits, u32, out_arr);
}

/// Convert f32 lanes to bfloat16 format in lower 16 bits of u32 (VCVTNEPS2BF16).
pub fn cvtF32ToBF16(comptime bits: usize, src: Wide(bits)) Wide(bits) {
    const lanes = comptime laneCount(bits, f32);
    const in_arr = toArray(bits, f32, src);
    var out_arr: [lanes]u32 = undefined;
    for (0..lanes) |lane| {
        const bits32 = @as(u32, @bitCast(in_arr[lane]));
        // Round to nearest even for bf16 truncation
        const rounding_bias = @as(u32, 0x7FFF + ((bits32 >> 16) & 1));
        const bf16_bits = (bits32 + rounding_bias) >> 16;
        out_arr[lane] = @as(u32, bf16_bits) & 0xFFFF;
    }
    return fromArray(bits, u32, out_arr);
}

// ──── P1 operations: UNPACK interleave (low/high) ──────────────────────

/// Unpack and interleave the low halves of two vectors per 128-bit block (PUNPCKL).
pub fn unpackLow(comptime bits: usize, comptime T: type, lhs: Wide(bits), rhs: Wide(bits)) Wide(bits) {
    const lanes_per_block = comptime types.laneCount(128, T);
    const blocks = comptime bits / 128;
    const total_lanes = comptime types.laneCount(bits, T);
    const a = toArray(bits, T, lhs);
    const b = toArray(bits, T, rhs);
    var out_arr: [total_lanes]T = undefined;
    for (0..blocks) |block| {
        const blk = block * lanes_per_block;
        const half = lanes_per_block / 2;
        for (0..half) |lane| {
            out_arr[blk + lane * 2 + 0] = a[blk + lane];
            out_arr[blk + lane * 2 + 1] = b[blk + lane];
        }
    }
    return fromArray(bits, T, out_arr);
}

/// Unpack and interleave the high halves of two vectors per 128-bit block (PUNPCKH).
pub fn unpackHigh(comptime bits: usize, comptime T: type, lhs: Wide(bits), rhs: Wide(bits)) Wide(bits) {
    const lanes_per_block = comptime types.laneCount(128, T);
    const blocks = comptime bits / 128;
    const total_lanes = comptime types.laneCount(bits, T);
    const a = toArray(bits, T, lhs);
    const b = toArray(bits, T, rhs);
    var out_arr: [total_lanes]T = undefined;
    for (0..blocks) |block| {
        const blk = block * lanes_per_block;
        const half = lanes_per_block / 2;
        for (0..half) |lane| {
            out_arr[blk + lane * 2 + 0] = a[blk + half + lane];
            out_arr[blk + lane * 2 + 1] = b[blk + half + lane];
        }
    }
    return fromArray(bits, T, out_arr);
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

test "CLEO broadcasts f32 scalar to all 256-bit lanes" {
    const scalar: f32 = 3.14;
    const result = broadcast(256, f32, scalar);
    const lanes = toArray(256, f32, result);
    try std.testing.expectEqual(@as(f32, 3.14), lanes[0]);
    try std.testing.expectEqual(@as(f32, 3.14), lanes[7]);
}

test "CLEO broadcasts u64 scalar to all 512-bit lanes" {
    const scalar: u64 = 0xDEADBEEF;
    const result = broadcast(512, u64, scalar);
    const lanes = toArray(512, u64, result);
    for (lanes) |lane| try std.testing.expectEqual(scalar, lane);
}

test "CLEO shuffles packed double lanes and applies AVX512 masks" {
    const merge = fromArray(512, u64, .{ 100, 101, 102, 103, 104, 105, 106, 107 });
    const lhs = fromArray(512, u64, .{ 1, 2, 3, 4, 5, 6, 7, 8 });
    const rhs = fromArray(512, u64, .{ 10, 20, 30, 40, 50, 60, 70, 80 });
    const out = shuffleImmediatePDMasked(512, merge, lhs, rhs, 0b10_01_10_01, 0b01010101, .merge);
    try std.testing.expectEqual([_]u64{ 2, 101, 3, 103, 6, 105, 7, 107 }, toArray(512, u64, out));
}
