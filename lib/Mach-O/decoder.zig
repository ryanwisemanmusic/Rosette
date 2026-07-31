const std = @import("std");
const builtin = @import("builtin");
const x64_decoder = @import("x64_decoder");

const Regs = x64_decoder.Regs;
const Size = x64_decoder.OperandSize;
const RegId = x64_decoder.RegId;
const Cond = x64_decoder.Condition;
const Op = x64_decoder.Op;
const DecodedInsn = x64_decoder.DecodedInsn;
const BitScanKind = x64_decoder.BitScanKind;
const bitScan = x64_decoder.bitScan;
const crc32cAccumulator = x64_decoder.crc32cAccumulator;

const RFL_CF = x64_decoder.RFL_CF;
const RFL_ZF = x64_decoder.RFL_ZF;
const RFL_SF = x64_decoder.RFL_SF;
const RFL_OF = x64_decoder.RFL_OF;

pub fn decodeInsn(bytes: []const u8) DecodedInsn {
    return x64_decoder.decodeLegacyInstruction(bytes, .long64);
}

pub fn decodeInsnCompat(bytes: []const u8) DecodedInsn {
    return x64_decoder.decodeLegacyInstruction(bytes, .compatibility);
}

pub const x87BinaryOperation = x64_decoder.x87BinaryOperation;
pub const decodeVex2 = x64_decoder.decodeVex2;
pub const decodeVex3 = x64_decoder.decodeVex3;
pub const decodeVexHalfMove = x64_decoder.decodeVexHalfMove;
pub const decodeVexDuplicateMove = x64_decoder.decodeVexDuplicateMove;
pub const decodeAccumulatorImmediate = x64_decoder.decodeAccumulatorImmediate;
pub const decodeTwoByte = x64_decoder.decodeTwoByte;
pub const decodeThreeByte = x64_decoder.decodeThreeByte;
pub const decodeSseBytes = x64_decoder.decodeSseBytes;
pub const hasModRM = x64_decoder.hasModRM;
pub const mapReg = x64_decoder.mapReg;
pub const mapJccCond8 = x64_decoder.mapJccCond8;
pub const mapJccCond32 = x64_decoder.mapJccCond32;
pub const readModRM = x64_decoder.readModRM;
pub const decodeArithRmReg = x64_decoder.decodeArithRmReg;
pub const decodeMovRmReg = x64_decoder.decodeMovRmReg;
pub const decodeLea = x64_decoder.decodeLea;
pub const decodePopRm = x64_decoder.decodePopRm;
pub const decodeGroup1Imm = x64_decoder.decodeGroup1Imm;
pub const decodeGroup2Shift = x64_decoder.decodeGroup2Shift;
pub const decodeMovMemImm = x64_decoder.decodeMovMemImm;
pub const decodeGroup3 = x64_decoder.decodeGroup3;
pub const decodeGroup4_5 = x64_decoder.decodeGroup4_5;
pub const decodeTestRmReg = x64_decoder.decodeTestRmReg;
pub const decodeXchgRmReg = x64_decoder.decodeXchgRmReg;
pub const decodeImulImm = x64_decoder.decodeImulImm;
pub const decodeImulTwoOp = x64_decoder.decodeImulTwoOp;
pub const decodeCmpxchg = x64_decoder.decodeCmpxchg;
pub const decodeMovzx = x64_decoder.decodeMovzx;
pub const decodeMovsx = x64_decoder.decodeMovsx;
pub const decodeXadd = x64_decoder.decodeXadd;
pub const decodeSetcc = x64_decoder.decodeSetcc;
pub const decodeMovupsMovss = x64_decoder.decodeMovupsMovss;
pub const decodeMovaps = x64_decoder.decodeMovaps;

pub const VexArithmetic = enum { add, multiply, subtract, divide };
pub const VexBitwise = enum { @"and", and_not, @"or", xor };
pub fn shuffleBytes(source: [16]u8, mask: [16]u8) [16]u8 {
    var result = [_]u8{0} ** 16;
    for (mask, 0..) |selector, index| {
        if (selector & 0x80 == 0) result[index] = source[selector & 0x0F];
    }
    return result;
}

pub fn compareEqualDwords(lhs: [16]u8, rhs: [16]u8) [16]u8 {
    var result: [16]u8 = undefined;
    for (0..4) |lane| {
        const offset = lane * 4;
        const left = std.mem.readInt(u32, lhs[offset..][0..4], .little);
        const right = std.mem.readInt(u32, rhs[offset..][0..4], .little);
        std.mem.writeInt(u32, result[offset..][0..4], if (left == right) std.math.maxInt(u32) else 0, .little);
    }
    return result;
}

pub fn unpackLowDwords(lhs: [16]u8, rhs: [16]u8) [16]u8 {
    var result: [16]u8 = undefined;
    @memcpy(result[0..4], lhs[0..4]);
    @memcpy(result[4..8], rhs[0..4]);
    @memcpy(result[8..12], lhs[4..8]);
    @memcpy(result[12..16], rhs[4..8]);
    return result;
}

pub fn permutePackedDoubles(source: [16]u8, control: u8) [16]u8 {
    var result: [16]u8 = undefined;
    const low_source: usize = if (control & 0x01 == 0) 0 else 8;
    const high_source: usize = if (control & 0x02 == 0) 0 else 8;
    @memcpy(result[0..8], source[low_source..][0..8]);
    @memcpy(result[8..16], source[high_source..][0..8]);
    return result;
}

pub fn bitwiseAndAllZero(a: [16]u8, b: [16]u8) bool {
    for (a, b) |ai, bi| if (ai & bi != 0) return false;
    return true;
}

pub fn bitwiseAndNotAllZero(a: [16]u8, b: [16]u8) bool {
    for (a, b) |ai, bi| if (~ai & bi != 0) return false;
    return true;
}

pub fn applyVexCompare(lhs: [16]u8, rhs: [16]u8, op: Op) [16]u8 {
    var result: [16]u8 = undefined;
    switch (op) {
        .vpcmpeqb => {
            for (&result, lhs, rhs) |*dst, l, r| dst.* = if (l == r) 0xFF else 0x00;
        },
        .vpcmpgtb => {
            for (&result, lhs, rhs) |*dst, l, r| dst.* = if (@as(i8, @bitCast(l)) > @as(i8, @bitCast(r))) 0xFF else 0x00;
        },
        .vpcmpeqw => {
            for (0..8) |lane| {
                const off = lane * 2;
                const l = std.mem.readInt(u16, lhs[off..][0..2], .little);
                const r = std.mem.readInt(u16, rhs[off..][0..2], .little);
                const mask: u16 = if (l == r) 0xFFFF else 0x0000;
                std.mem.writeInt(u16, result[off..][0..2], mask, .little);
            }
        },
        .vpcmpgtw => {
            for (0..8) |lane| {
                const off = lane * 2;
                const l: i16 = @bitCast(std.mem.readInt(u16, lhs[off..][0..2], .little));
                const r: i16 = @bitCast(std.mem.readInt(u16, rhs[off..][0..2], .little));
                const mask: u16 = if (l > r) 0xFFFF else 0x0000;
                std.mem.writeInt(u16, result[off..][0..2], mask, .little);
            }
        },
        .vpcmpeqd => {
            for (0..4) |lane| {
                const off = lane * 4;
                const l = std.mem.readInt(u32, lhs[off..][0..4], .little);
                const r = std.mem.readInt(u32, rhs[off..][0..4], .little);
                const mask: u32 = if (l == r) std.math.maxInt(u32) else 0;
                std.mem.writeInt(u32, result[off..][0..4], mask, .little);
            }
        },
        .vpcmpeqq => {
            for (0..2) |lane| {
                const off = lane * 8;
                const l = std.mem.readInt(u64, lhs[off..][0..8], .little);
                const r = std.mem.readInt(u64, rhs[off..][0..8], .little);
                const mask: u64 = if (l == r) std.math.maxInt(u64) else 0;
                std.mem.writeInt(u64, result[off..][0..8], mask, .little);
            }
        },
        .vpcmpgtd => {
            for (0..4) |lane| {
                const off = lane * 4;
                const l: i32 = @bitCast(std.mem.readInt(u32, lhs[off..][0..4], .little));
                const r: i32 = @bitCast(std.mem.readInt(u32, rhs[off..][0..4], .little));
                const mask: u32 = if (l > r) std.math.maxInt(u32) else 0;
                std.mem.writeInt(u32, result[off..][0..4], mask, .little);
            }
        },
        .vpcmpgtq => {
            for (0..2) |lane| {
                const off = lane * 8;
                const l: i64 = @bitCast(std.mem.readInt(u64, lhs[off..][0..8], .little));
                const r: i64 = @bitCast(std.mem.readInt(u64, rhs[off..][0..8], .little));
                const mask: u64 = if (l > r) std.math.maxInt(u64) else 0;
                std.mem.writeInt(u64, result[off..][0..8], mask, .little);
            }
        },
        else => unreachable,
    }
    return result;
}

pub fn vexArithmeticForOp(op: Op) VexArithmetic {
    return switch (op) {
        .vaddss, .vaddsd, .vaddps, .vaddpd => .add,
        .vmulss, .vmulsd, .vmulps, .vmulpd => .multiply,
        .vsubss, .vsubsd, .vsubps, .vsubpd => .subtract,
        .vdivss, .vdivsd, .vdivps, .vdivpd => .divide,
        else => unreachable,
    };
}

pub fn applyVexArithmetic(comptime Float: type, lhs: Float, rhs: Float, operation: VexArithmetic) Float {
    return switch (operation) {
        .add => lhs + rhs,
        .multiply => lhs * rhs,
        .subtract => lhs - rhs,
        .divide => lhs / rhs,
    };
}

pub fn vexBitwiseForOp(op: Op) VexBitwise {
    return switch (op) {
        .vandps, .vandpd, .vpand => .@"and",
        .vandnps, .vandnpd, .vpandn => .and_not,
        .vorps, .vorpd, .vpor => .@"or",
        .vxorps, .vxorpd, .vpxor => .xor,
        else => unreachable,
    };
}

pub fn applyVexBitwise(lhs: [16]u8, rhs: [16]u8, operation: VexBitwise) [16]u8 {
    var result: [16]u8 = undefined;
    for (&result, lhs, rhs) |*destination, left, right| {
        destination.* = switch (operation) {
            .@"and" => left & right,
            .and_not => ~left & right,
            .@"or" => left | right,
            .xor => left ^ right,
        };
    }
    return result;
}

pub fn applyVexPackedF32(lhs: [16]u8, rhs: [16]u8, operation: VexArithmetic) [16]u8 {
    var result: [16]u8 = undefined;
    for (0..4) |lane| {
        const offset = lane * 4;
        const lhs_value: f32 = @bitCast(std.mem.readInt(u32, lhs[offset..][0..4], .little));
        const rhs_value: f32 = @bitCast(std.mem.readInt(u32, rhs[offset..][0..4], .little));
        std.mem.writeInt(u32, result[offset..][0..4], @bitCast(applyVexArithmetic(f32, lhs_value, rhs_value, operation)), .little);
    }
    return result;
}

pub fn applyVexPackedF64(lhs: [16]u8, rhs: [16]u8, operation: VexArithmetic) [16]u8 {
    var result: [16]u8 = undefined;
    for (0..2) |lane| {
        const offset = lane * 8;
        const lhs_value: f64 = @bitCast(std.mem.readInt(u64, lhs[offset..][0..8], .little));
        const rhs_value: f64 = @bitCast(std.mem.readInt(u64, rhs[offset..][0..8], .little));
        std.mem.writeInt(u64, result[offset..][0..8], @bitCast(applyVexArithmetic(f64, lhs_value, rhs_value, operation)), .little);
    }
    return result;
}

pub fn sqrtVexPackedF32(source: [16]u8) [16]u8 {
    var result: [16]u8 = undefined;
    for (0..4) |lane| {
        const offset = lane * 4;
        const source_value: f32 = @bitCast(std.mem.readInt(u32, source[offset..][0..4], .little));
        std.mem.writeInt(u32, result[offset..][0..4], @bitCast(@sqrt(source_value)), .little);
    }
    return result;
}

pub fn sqrtVexPackedF64(source: [16]u8) [16]u8 {
    var result: [16]u8 = undefined;
    for (0..2) |lane| {
        const offset = lane * 8;
        const source_value: f64 = @bitCast(std.mem.readInt(u64, source[offset..][0..8], .little));
        std.mem.writeInt(u64, result[offset..][0..8], @bitCast(@sqrt(source_value)), .little);
    }
    return result;
}

pub fn roundVexFloat(comptime Float: type, value: Float, immediate: u8) Float {
    if (std.math.isNan(value) or std.math.isInf(value)) return value;
    const mode: u2 = if (immediate & 0x04 != 0) 0 else @truncate(immediate);
    return switch (mode) {
        0 => roundNearestEven(Float, value),
        1 => @floor(value),
        2 => @ceil(value),
        3 => @trunc(value),
    };
}

pub fn roundNearestEven(comptime Float: type, value: Float) Float {
    const lower = @floor(value);
    const fraction = value - lower;
    const half: Float = 0.5;
    if (fraction < half) return lower;
    if (fraction > half) return lower + 1.0;
    return if (@mod(lower, 2.0) == 0.0) lower else lower + 1.0;
}

pub fn roundVexPackedF32(source: [16]u8, immediate: u8) [16]u8 {
    var result: [16]u8 = undefined;
    for (0..4) |lane| {
        const offset = lane * 4;
        const value: f32 = @bitCast(std.mem.readInt(u32, source[offset..][0..4], .little));
        std.mem.writeInt(u32, result[offset..][0..4], @bitCast(roundVexFloat(f32, value, immediate)), .little);
    }
    return result;
}

pub fn roundVexPackedF64(source: [16]u8, immediate: u8) [16]u8 {
    var result: [16]u8 = undefined;
    for (0..2) |lane| {
        const offset = lane * 8;
        const value: f64 = @bitCast(std.mem.readInt(u64, source[offset..][0..8], .little));
        std.mem.writeInt(u64, result[offset..][0..8], @bitCast(roundVexFloat(f64, value, immediate)), .little);
    }
    return result;
}

pub fn convertVexFloatToSigned(comptime Float: type, value: Float, size: Size, truncate: bool) u64 {
    const rounded = if (truncate) @trunc(value) else roundNearestEven(Float, value);
    if (std.math.isNan(rounded)) return integerIndefinite(size);

    return switch (size) {
        .bits32 => blk: {
            const minimum: Float = -2147483648.0;
            const maximum_exclusive: Float = 2147483648.0;
            if (rounded < minimum or rounded >= maximum_exclusive) break :blk integerIndefinite(size);
            const signed: i32 = @intFromFloat(rounded);
            break :blk @as(u32, @bitCast(signed));
        },
        .bits64 => blk: {
            const minimum: Float = -9223372036854775808.0;
            const maximum_exclusive: Float = 9223372036854775808.0;
            if (rounded < minimum or rounded >= maximum_exclusive) break :blk integerIndefinite(size);
            const signed: i64 = @intFromFloat(rounded);
            break :blk @bitCast(signed);
        },
        else => unreachable,
    };
}

pub fn integerIndefinite(size: Size) u64 {
    return if (size == .bits64) @as(u64, 1) << 63 else @as(u64, 1) << 31;
}

pub fn duplicateVectorElements(op: Op, source: [16]u8) [16]u8 {
    var result: [16]u8 = undefined;
    switch (op) {
        .vmovshdup => {
            result[0..4].* = source[4..8].*;
            result[4..8].* = source[4..8].*;
            result[8..12].* = source[12..16].*;
            result[12..16].* = source[12..16].*;
        },
        .vmovsldup => {
            result[0..4].* = source[0..4].*;
            result[4..8].* = source[0..4].*;
            result[8..12].* = source[8..12].*;
            result[12..16].* = source[8..12].*;
        },
        .vmovddup => {
            result[0..8].* = source[0..8].*;
            result[8..16].* = source[0..8].*;
        },
        else => unreachable,
    }
    return result;
}

test "CMPXCHG decoder preserves opcode-selected operand width" {
    // Xenia's TimerQueue compare_exchange_strong emits this exact instruction.
    const byte_memory = decodeInsn(&[_]u8{ 0xF0, 0x0F, 0xB0, 0x11 });
    try std.testing.expectEqual(Op.cmpxchg_mem8_reg8, byte_memory.op);
    try std.testing.expectEqual(Size.bits8, byte_memory.size);
    try std.testing.expectEqual(RegId.dl_dx_edx_rdx, byte_memory.src_reg);
    try std.testing.expectEqual(RegId.cl_cx_ecx_rcx, byte_memory.sib_base_reg);
    try std.testing.expect(byte_memory.lock);

    const word_memory = decodeInsn(&[_]u8{ 0xF0, 0x66, 0x0F, 0xB1, 0x11 });
    try std.testing.expectEqual(Op.cmpxchg_mem16_reg16, word_memory.op);
    try std.testing.expectEqual(Size.bits16, word_memory.size);

    const dword_memory = decodeInsn(&[_]u8{ 0xF0, 0x0F, 0xB1, 0x11 });
    try std.testing.expectEqual(Op.cmpxchg_mem32_reg32, dword_memory.op);
    try std.testing.expectEqual(Size.bits32, dword_memory.size);

    const qword_memory = decodeInsn(&[_]u8{ 0xF0, 0x48, 0x0F, 0xB1, 0x11 });
    try std.testing.expectEqual(Op.cmpxchg_mem64_reg64, qword_memory.op);
    try std.testing.expectEqual(Size.bits64, qword_memory.size);
}
