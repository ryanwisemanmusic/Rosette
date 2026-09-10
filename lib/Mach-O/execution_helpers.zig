//! x86-64 instruction execution helper functions.
//! Extracted from MachOState (process.zig) to reduce file size.
//!
//! Uses `anytype` for the `self` parameter to avoid circular imports.
//! The type is inferred at the call site as `*MachOState`.

const std = @import("std");
const x64_decoder = @import("x64_decoder");

const DecodedInsn = x64_decoder.DecodedInsn;
const BitScanKind = x64_decoder.BitScanKind;
const bitScan = x64_decoder.bitScan;
const decoder = @import("decoder.zig");
const packed_ops = @import("packed_ops.zig");
/// Public aliases let the PE/ELF executor share the exact operation mapping
/// used by the Mach-O executor without duplicating the arithmetic enum.  The
/// implementations below remain backend-agnostic (`anytype` self), so this
/// module is intentionally safe to use from both processor front-ends.
pub const VexArithmetic = @import("decoder.zig").VexArithmetic;
pub const VexBitwise = @import("decoder.zig").VexBitwise;
pub const PackedIntegerOperation = packed_ops.PackedIntegerOperation;
pub const PackedPackOperation = packed_ops.PackedPackOperation;
pub const MinMaxKind = packed_ops.MinMaxKind;
const applyVexArithmetic = @import("decoder.zig").applyVexArithmetic;
const applyVexPackedF32 = @import("decoder.zig").applyVexPackedF32;
const applyVexPackedF64 = @import("decoder.zig").applyVexPackedF64;
const applyVexBitwise = @import("decoder.zig").applyVexBitwise;
const sqrtVexPackedF32 = @import("decoder.zig").sqrtVexPackedF32;
const sqrtVexPackedF64 = @import("decoder.zig").sqrtVexPackedF64;

const RFL_CF = x64_decoder.RFL_CF;
const RFL_PF: u32 = 1 << 2;
const RFL_AF: u32 = 1 << 4;
const RFL_ZF = x64_decoder.RFL_ZF;
const RFL_SF = x64_decoder.RFL_SF;
const RFL_OF = x64_decoder.RFL_OF;
const Size = x64_decoder.OperandSize;

pub fn bitWidth(size: Size) u7 {
    return switch (size) {
        .bits8 => 8,
        .bits16 => 16,
        .bits32 => 32,
        .bits64 => 64,
    };
}

pub fn maskForSize(size: Size) u64 {
    return switch (size) {
        .bits8 => 0xFF,
        .bits16 => 0xFFFF,
        .bits32 => 0xFFFF_FFFF,
        .bits64 => 0xFFFF_FFFF_FFFF_FFFF,
    };
}

pub fn signBitForSize(size: Size) u64 {
    return switch (size) {
        .bits8 => 0x80,
        .bits16 => 0x8000,
        .bits32 => 0x8000_0000,
        .bits64 => 0x8000_0000_0000_0000,
    };
}

/// Sign-extends a value from `source_size` to `destination_size` while
/// preserving the architectural destination width. In particular, REX.W
/// MOVSX must extend through all 64 bits rather than first producing a u32
/// that is subsequently zero-extended by the register write.
pub fn signExtend(value: u64, source_size: Size, destination_size: Size) u64 {
    const source_mask = maskForSize(source_size);
    const truncated = value & source_mask;
    const extended = if (truncated & signBitForSize(source_size) != 0)
        truncated | ~source_mask
    else
        truncated;
    return extended & maskForSize(destination_size);
}

/// Produce the architectural integer flags for the x87 *I comparison family.
/// These instructions write ZF/PF/CF and explicitly clear OF/SF/AF; every
/// other RFLAGS bit is preserved. The unordered result is represented by all
/// three comparison flags set, matching the x86 contract used by FCMOVU and
/// its inverse conditions.
pub fn x87CompareFlags(rflags: u32, lhs: f64, rhs: f64) u32 {
    var result = rflags & ~(RFL_ZF | RFL_PF | RFL_CF | RFL_OF | RFL_SF | RFL_AF);
    if (std.math.isNan(lhs) or std.math.isNan(rhs)) {
        result |= RFL_ZF | RFL_PF | RFL_CF;
    } else if (lhs < rhs) {
        result |= RFL_CF;
    } else if (lhs == rhs) {
        result |= RFL_ZF;
    }
    return result;
}

pub fn executeX87Compare(self: anytype, source: u3, pop_result: bool) void {
    const lhs = self.x87.get(0) orelse return;
    const rhs = self.x87.get(source) orelse return;
    self.regs.rflags = x87CompareFlags(self.regs.rflags, lhs, rhs);
    if (pop_result) _ = self.x87.pop();
}

pub fn executeFucomi(self: anytype, source: u3) void {
    executeX87Compare(self, source, false);
}

pub fn executeFcomi(self: anytype, source: u3) void {
    // The current guest x87 model has masked exceptions and no separate
    // invalid-operation delivery path, so the observable integer flags are
    // the same as FUCOMI for the supported finite/unordered values.
    executeX87Compare(self, source, false);
}

pub fn executeFucomip(self: anytype, source: u3) void {
    executeX87Compare(self, source, true);
}

pub fn executeFcomip(self: anytype, source: u3) void {
    executeX87Compare(self, source, true);
}

pub fn executeFcmov(self: anytype, source: u3, condition: x64_decoder.Condition) void {
    if (!x64_decoder.evalCond(self.regs.rflags, condition)) return;
    const value = self.x87.get(source) orelse return;
    _ = self.x87.set(0, value);
}

test "x87 integer compare flags clear the explicitly cleared flags" {
    const initial = RFL_CF | RFL_PF | RFL_AF | RFL_ZF | RFL_SF | RFL_OF | (1 << 9);
    const less = x87CompareFlags(initial, 1.0, 2.0);
    try std.testing.expectEqual(@as(u32, (1 << 9) | RFL_CF), less);

    const unordered = x87CompareFlags(initial, std.math.nan(f64), 2.0);
    try std.testing.expectEqual(@as(u32, (1 << 9) | RFL_ZF | RFL_PF | RFL_CF), unordered);
}

test "sign extension honors the full architectural destination width" {
    try std.testing.expectEqual(@as(u64, 0xFFFF_FFFF_FFFF_FF80), signExtend(0x80, .bits8, .bits64));
    try std.testing.expectEqual(@as(u64, 0x0000_0000_FFFF_FF80), signExtend(0x80, .bits8, .bits32));
    try std.testing.expectEqual(@as(u64, 0xFFFF_FFFF_FFFF_8000), signExtend(0x8000, .bits16, .bits64));
    try std.testing.expectEqual(@as(u64, 0xFFFF_FFFF_8000_0000), signExtend(0x8000_0000, .bits32, .bits64));
    try std.testing.expectEqual(@as(u64, 0x7F), signExtend(0x7F, .bits8, .bits64));
}

pub fn executeBitScan(self: anytype, d: DecodedInsn) void {
    const is_memory = switch (d.op) {
        .bsf_reg_mem, .bsr_reg_mem, .tzcnt_reg_mem, .lzcnt_reg_mem => true,
        else => false,
    };
    const kind: BitScanKind = switch (d.op) {
        .bsf_reg_reg, .bsf_reg_mem => .bsf,
        .bsr_reg_reg, .bsr_reg_mem => .bsr,
        .tzcnt_reg_reg, .tzcnt_reg_mem => .tzcnt,
        .lzcnt_reg_reg, .lzcnt_reg_mem => .lzcnt,
        else => unreachable,
    };
    const source = if (is_memory) self.readMemVal(d.addr, d.size) else self.regVal(d.src_reg, d.size);
    const result = bitScan(d.size, kind, source);

    if (result.write_destination) self.setReg(d.dst_reg, d.size, result.value);
    self.setFlag(RFL_ZF, result.zero_flag);
    if (result.carry_flag) |carry| self.setFlag(RFL_CF, carry);
}

pub fn executeRotate(self: anytype, d: DecodedInsn) void {
    const is_mem = switch (d.op) {
        .rol_mem_cl, .ror_mem_cl, .rol_mem_imm, .ror_mem_imm => true,
        else => false,
    };
    const rotate_left = switch (d.op) {
        .rol_reg_cl, .rol_mem_cl, .rol_reg_imm, .rol_mem_imm => true,
        else => false,
    };
    const uses_cl = switch (d.op) {
        .rol_reg_cl, .rol_mem_cl, .ror_reg_cl, .ror_mem_cl => true,
        else => false,
    };
    const raw_count = if (uses_cl) self.regVal(.cl_cx_ecx_rcx, .bits8) else d.imm;
    const masked_count = raw_count & @as(u64, if (d.size == .bits64) 0x3F else 0x1F);
    const width: u64 = bitWidth(d.size);
    const count: u6 = @intCast(masked_count % width);
    if (count == 0) return;

    const mask = maskForSize(d.size);
    const old = (if (is_mem) self.readMemVal(d.addr, d.size) else self.regVal(d.dst_reg, d.size)) & mask;
    const inverse: u6 = @intCast(width - count);
    const result = if (rotate_left)
        ((old << count) | (old >> inverse)) & mask
    else
        ((old >> count) | (old << inverse)) & mask;

    if (is_mem) self.writeMemVal(d.addr, d.size, result) else self.setReg(d.dst_reg, d.size, result);
    if (rotate_left) {
        const carry = (result & 1) != 0;
        self.setFlag(RFL_CF, carry);
        if (count == 1) self.setFlag(RFL_OF, ((result & signBitForSize(d.size)) != 0) != carry);
    } else {
        const carry = (result & signBitForSize(d.size)) != 0;
        self.setFlag(RFL_CF, carry);
        if (count == 1) {
            const next_sign = (result & (signBitForSize(d.size) >> 1)) != 0;
            self.setFlag(RFL_OF, carry != next_sign);
        }
    }
}

pub fn executeVexScalarF32(self: anytype, d: DecodedInsn, operation: VexArithmetic) void {
    const source1 = self.xmm[d.xmm_src];
    const source2_bits = if (d.is_reg_form)
        std.mem.readInt(u32, self.xmm[d.xmm_src2][0..4], .little)
    else
        @as(u32, @truncate(self.readMemVal(d.addr, .bits32)));
    const source1_value: f32 = @bitCast(std.mem.readInt(u32, source1[0..4], .little));
    const source2_value: f32 = @bitCast(source2_bits);

    self.xmm[d.xmm_dst] = source1;
    std.mem.writeInt(u32, self.xmm[d.xmm_dst][0..4], @bitCast(applyVexArithmetic(f32, source1_value, source2_value, operation)), .little);
    if (!d.legacy_sse) @memset(&self.ymm_hi[d.xmm_dst], 0);
}

pub fn executeVexScalarF64(self: anytype, d: DecodedInsn, operation: VexArithmetic) void {
    const source1 = self.xmm[d.xmm_src];
    const source2_bits = if (d.is_reg_form)
        std.mem.readInt(u64, self.xmm[d.xmm_src2][0..8], .little)
    else
        self.readMemVal(d.addr, .bits64);
    const source1_value: f64 = @bitCast(std.mem.readInt(u64, source1[0..8], .little));
    const source2_value: f64 = @bitCast(source2_bits);

    self.xmm[d.xmm_dst] = source1;
    std.mem.writeInt(u64, self.xmm[d.xmm_dst][0..8], @bitCast(applyVexArithmetic(f64, source1_value, source2_value, operation)), .little);
    if (!d.legacy_sse) @memset(&self.ymm_hi[d.xmm_dst], 0);
}

pub fn executeVexPackedF32(self: anytype, d: DecodedInsn, operation: VexArithmetic) void {
    const source1_low = self.xmm[d.xmm_src];
    const source2_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
    self.xmm[d.xmm_dst] = applyVexPackedF32(source1_low, source2_low, operation);

    if (d.vector_256) {
        const source1_high = self.ymm_hi[d.xmm_src];
        const source2_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
        self.ymm_hi[d.xmm_dst] = applyVexPackedF32(source1_high, source2_high, operation);
    } else if (!d.legacy_sse) {
        @memset(&self.ymm_hi[d.xmm_dst], 0);
    }
}

pub fn executeVexPackedF64(self: anytype, d: DecodedInsn, operation: VexArithmetic) void {
    const source1_low = self.xmm[d.xmm_src];
    const source2_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
    self.xmm[d.xmm_dst] = applyVexPackedF64(source1_low, source2_low, operation);

    if (d.vector_256) {
        const source1_high = self.ymm_hi[d.xmm_src];
        const source2_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
        self.ymm_hi[d.xmm_dst] = applyVexPackedF64(source1_high, source2_high, operation);
    } else if (!d.legacy_sse) {
        @memset(&self.ymm_hi[d.xmm_dst], 0);
    }
}

fn unpackPackedFloat128(
    lhs: [16]u8,
    rhs: [16]u8,
    comptime element_bytes: usize,
    high: bool,
) [16]u8 {
    var result = [_]u8{0} ** 16;
    const lanes_per_half = 8 / element_bytes;
    const source_lane_base = if (high) lanes_per_half else 0;
    for (0..lanes_per_half) |lane| {
        const source_offset = (source_lane_base + lane) * element_bytes;
        const destination_offset = lane * 2 * element_bytes;
        @memcpy(result[destination_offset..][0..element_bytes], lhs[source_offset..][0..element_bytes]);
        @memcpy(result[destination_offset + element_bytes ..][0..element_bytes], rhs[source_offset..][0..element_bytes]);
    }
    return result;
}

/// Execute the AVX packed floating-point unpack family. Each 128-bit lane is
/// interleaved independently; VEX.128 also clears the destination's upper YMM
/// half, while VEX.256 computes the second lane from the upper inputs.
pub fn executeVexPackedUnpack(self: anytype, d: DecodedInsn) void {
    const high = d.op == .vunpckhps or d.op == .vunpckhpd;
    const double = d.op == .vunpcklpd or d.op == .vunpckhpd;

    const source2_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
    self.xmm[d.xmm_dst] = if (double)
        unpackPackedFloat128(self.xmm[d.xmm_src], source2_low, 8, high)
    else
        unpackPackedFloat128(self.xmm[d.xmm_src], source2_low, 4, high);

    if (d.vector_256) {
        const source2_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
        self.ymm_hi[d.xmm_dst] = if (double)
            unpackPackedFloat128(self.ymm_hi[d.xmm_src], source2_high, 8, high)
        else
            unpackPackedFloat128(self.ymm_hi[d.xmm_src], source2_high, 4, high);
    } else if (!d.legacy_sse) {
        @memset(&self.ymm_hi[d.xmm_dst], 0);
    }
}

pub fn executeVexSqrtScalarF32(self: anytype, d: DecodedInsn) void {
    const source_bits = if (d.is_reg_form)
        std.mem.readInt(u32, self.xmm[d.xmm_src2][0..4], .little)
    else
        @as(u32, @truncate(self.readMemVal(d.addr, .bits32)));
    const source_value: f32 = @bitCast(source_bits);

    self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
    std.mem.writeInt(u32, self.xmm[d.xmm_dst][0..4], @bitCast(@sqrt(source_value)), .little);
    if (!d.legacy_sse) @memset(&self.ymm_hi[d.xmm_dst], 0);
}

pub fn executeVexSqrtScalarF64(self: anytype, d: DecodedInsn) void {
    const source_bits = if (d.is_reg_form)
        std.mem.readInt(u64, self.xmm[d.xmm_src2][0..8], .little)
    else
        self.readMemVal(d.addr, .bits64);
    const source_value: f64 = @bitCast(source_bits);

    self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
    std.mem.writeInt(u64, self.xmm[d.xmm_dst][0..8], @bitCast(@sqrt(source_value)), .little);
    if (!d.legacy_sse) @memset(&self.ymm_hi[d.xmm_dst], 0);
}

pub fn executeVexSqrtPackedF32(self: anytype, d: DecodedInsn) void {
    const source_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
    self.xmm[d.xmm_dst] = sqrtVexPackedF32(source_low);
    if (d.vector_256) {
        const source_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
        self.ymm_hi[d.xmm_dst] = sqrtVexPackedF32(source_high);
    } else if (!d.legacy_sse) {
        @memset(&self.ymm_hi[d.xmm_dst], 0);
    }
}

pub fn executeVexSqrtPackedF64(self: anytype, d: DecodedInsn) void {
    const source_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
    self.xmm[d.xmm_dst] = sqrtVexPackedF64(source_low);
    if (d.vector_256) {
        const source_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
        self.ymm_hi[d.xmm_dst] = sqrtVexPackedF64(source_high);
    } else if (!d.legacy_sse) {
        @memset(&self.ymm_hi[d.xmm_dst], 0);
    }
}

pub fn setVexComparisonFlags(self: anytype, lhs: anytype, rhs: @TypeOf(lhs)) void {
    self.regs.rflags &= ~(RFL_OF | RFL_SF | RFL_ZF | RFL_AF | RFL_PF | RFL_CF);
    if (std.math.isNan(lhs) or std.math.isNan(rhs)) {
        self.regs.rflags |= RFL_ZF | RFL_PF | RFL_CF;
    } else if (lhs < rhs) {
        self.regs.rflags |= RFL_CF;
    } else if (lhs == rhs) {
        self.regs.rflags |= RFL_ZF;
    }
}

pub fn executeVexBitwise(self: anytype, d: DecodedInsn, operation: VexBitwise) void {
    const source1_low = self.xmm[d.xmm_src];
    const source2_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
    self.xmm[d.xmm_dst] = applyVexBitwise(source1_low, source2_low, operation);

    if (d.vector_256) {
        const source1_high = self.ymm_hi[d.xmm_src];
        const source2_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
        self.ymm_hi[d.xmm_dst] = applyVexBitwise(source1_high, source2_high, operation);
    } else if (!d.legacy_sse) {
        @memset(&self.ymm_hi[d.xmm_dst], 0);
    }
}

/// VCMPPS / VCMPPD — packed compare to a lane mask.
///
/// Returns false when the predicate is one this interpreter does not model, so
/// the caller leaves the instruction unexecuted instead of writing a mask built
/// from a guess. A wrong mask is a wrong branch in the guest with nothing
/// anywhere to indicate it happened.
pub fn executeVexComparePacked(self: anytype, d: DecodedInsn, comptime double: bool) bool {
    const predicate = decoder.VexComparePredicate.fromImmediate(@truncate(d.imm)) orelse return false;
    const compare = if (double) decoder.compareVexPackedF64 else decoder.compareVexPackedF32;

    const right_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
    self.xmm[d.xmm_dst] = compare(self.xmm[d.xmm_src], right_low, predicate);
    if (d.vector_256) {
        const right_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
        self.ymm_hi[d.xmm_dst] = compare(self.ymm_hi[d.xmm_src], right_high, predicate);
    } else if (!d.legacy_sse) {
        @memset(&self.ymm_hi[d.xmm_dst], 0);
    }
    return true;
}

/// VCMPSS / VCMPSD — scalar compare. Only the low lane is compared; the rest of
/// the destination is taken from the first source, which is what makes this a
/// merge rather than a write.
pub fn executeVexCompareScalar(self: anytype, d: DecodedInsn, comptime double: bool) bool {
    const predicate = decoder.VexComparePredicate.fromImmediate(@truncate(d.imm)) orelse return false;
    const width = if (double) 8 else 4;
    const Lane = if (double) u64 else u32;
    const Float = if (double) f64 else f32;

    const left: Float = @bitCast(std.mem.readInt(Lane, self.xmm[d.xmm_src][0..width], .little));
    const right_bits: Lane = if (d.is_reg_form)
        std.mem.readInt(Lane, self.xmm[d.xmm_src2][0..width], .little)
    else
        @truncate(self.readMemVal(d.addr, if (double) .bits64 else .bits32));
    const right: Float = @bitCast(right_bits);

    self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
    if (d.legacy_sse) @memset(self.xmm[d.xmm_dst][width..16], 0);
    const mask: Lane = if (predicate.evaluate(left, right)) ~@as(Lane, 0) else 0;
    std.mem.writeInt(Lane, self.xmm[d.xmm_dst][0..width], mask, .little);
    if (!d.legacy_sse) @memset(&self.ymm_hi[d.xmm_dst], 0);
    return true;
}

/// VCVTDQ2PS / VCVTPS2DQ / VCVTTPS2DQ — packed conversion between signed
/// dwords and singles. Two operands: the destination is written whole, so
/// unlike the scalar forms there is nothing to merge.
pub fn executeVexConvertPacked(
    self: anytype,
    d: DecodedInsn,
    comptime direction: enum { dword_to_float, float_to_dword_round, float_to_dword_truncate },
) void {
    const convert = struct {
        fn apply(source: [16]u8) [16]u8 {
            return switch (direction) {
                .dword_to_float => decoder.convertVexPackedDwordToFloat(source),
                .float_to_dword_round => decoder.convertVexPackedFloatToDword(source, false),
                .float_to_dword_truncate => decoder.convertVexPackedFloatToDword(source, true),
            };
        }
    }.apply;

    const source_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
    self.xmm[d.xmm_dst] = convert(source_low);
    if (d.vector_256) {
        const source_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
        self.ymm_hi[d.xmm_dst] = convert(source_high);
    } else {
        @memset(&self.ymm_hi[d.xmm_dst], 0);
    }
}

/// VCVTPS2PD/VCVTPD2PS have a different source and destination width from
/// the ordinary same-width packed conversions above. VEX.L selects the
/// source width for VCVTPD2PS and the destination width for VCVTPS2PD:
///
///   VCVTPD2PS xmm, xmm/m128   (L=0)
///   VCVTPD2PS xmm, ymm/m256   (L=1)
///   VCVTPS2PD xmm, xmm/m64    (L=0)
///   VCVTPS2PD ymm, xmm/m128   (L=1)
///
/// Keep the narrow/wide halves explicit so a register alias cannot overwrite
/// an input before all source lanes have been read.
pub fn executeVexConvertFloatPacked(
    self: anytype,
    d: DecodedInsn,
    comptime direction: enum { single_to_double, double_to_single },
) void {
    switch (direction) {
        .double_to_single => {
            const source_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
            const source_high = if (d.vector_256)
                (if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16))
            else
                [_]u8{0} ** 16;
            const lane_count: usize = if (d.vector_256) 4 else 2;
            var result = [_]u8{0} ** 16;
            for (0..lane_count) |lane| {
                const source = if (lane < 2) source_low else source_high;
                const source_offset = (lane % 2) * 8;
                const source_bits = std.mem.readInt(u64, source[source_offset..][0..8], .little);
                const converted: f32 = @floatCast(@as(f64, @bitCast(source_bits)));
                std.mem.writeInt(u32, result[lane * 4 ..][0..4], @bitCast(converted), .little);
            }
            self.xmm[d.xmm_dst] = result;
            // All VEX forms zero the destination YMM upper half. In the L=1
            // form the result is still an XMM register, despite the wider
            // source operand.
            @memset(&self.ymm_hi[d.xmm_dst], 0);
        },
        .single_to_double => {
            const source = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
            const lane_count: usize = if (d.vector_256) 4 else 2;
            var result_low = [_]u8{0} ** 16;
            var result_high = [_]u8{0} ** 16;
            for (0..lane_count) |lane| {
                const source_bits = std.mem.readInt(u32, source[lane * 4 ..][0..4], .little);
                const converted: f64 = @floatCast(@as(f32, @bitCast(source_bits)));
                const destination = if (lane < 2) &result_low else &result_high;
                const destination_offset = (lane % 2) * 8;
                std.mem.writeInt(u64, destination[destination_offset..][0..8], @bitCast(converted), .little);
            }
            self.xmm[d.xmm_dst] = result_low;
            if (d.vector_256) {
                self.ymm_hi[d.xmm_dst] = result_high;
            } else {
                @memset(&self.ymm_hi[d.xmm_dst], 0);
            }
        },
    }
}

/// VRCPPS / VRSQRTPS — packed approximate reciprocal. Two operands.
pub fn executeVexReciprocalPacked(self: anytype, d: DecodedInsn, comptime square_root: bool) void {
    const source_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
    self.xmm[d.xmm_dst] = decoder.reciprocalVexPackedF32(source_low, square_root);
    if (d.vector_256) {
        const source_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
        self.ymm_hi[d.xmm_dst] = decoder.reciprocalVexPackedF32(source_high, square_root);
    } else {
        @memset(&self.ymm_hi[d.xmm_dst], 0);
    }
}

/// VRCPSS / VRSQRTSS — scalar approximate reciprocal. Three operands: only the
/// low lane is computed, and the upper lanes come from the *first* source
/// rather than from the operand being reciprocated. Taking them from the wrong
/// place is invisible in any test that only inspects lane zero.
pub fn executeVexReciprocalScalar(self: anytype, d: DecodedInsn, comptime square_root: bool) void {
    const source_bits: u32 = if (d.is_reg_form)
        std.mem.readInt(u32, self.xmm[d.xmm_src2][0..4], .little)
    else
        @truncate(self.readMemVal(d.addr, .bits32));
    const value: f32 = @bitCast(source_bits);
    const computed = if (square_root)
        decoder.approximateReciprocalSqrt(value)
    else
        decoder.approximateReciprocal(value);

    self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
    std.mem.writeInt(u32, self.xmm[d.xmm_dst][0..4], @bitCast(computed), .little);
    @memset(&self.ymm_hi[d.xmm_dst], 0);
}

pub fn executeVexRoundScalarF32(self: anytype, d: DecodedInsn) void {
    const source1 = self.xmm[d.xmm_src];
    const source2_bits: u32 = if (d.is_reg_form)
        std.mem.readInt(u32, self.xmm[d.xmm_src2][0..4], .little)
    else
        @truncate(self.readMemVal(d.addr, .bits32));
    self.xmm[d.xmm_dst] = source1;
    std.mem.writeInt(u32, self.xmm[d.xmm_dst][0..4], @bitCast(decoder.roundVexFloat(f32, @as(f32, @bitCast(source2_bits)), @truncate(d.imm))), .little);
    @memset(&self.ymm_hi[d.xmm_dst], 0);
}

pub fn executeVexRoundScalarF64(self: anytype, d: DecodedInsn) void {
    const source1 = self.xmm[d.xmm_src];
    const source2_bits: u64 = if (d.is_reg_form)
        std.mem.readInt(u64, self.xmm[d.xmm_src2][0..8], .little)
    else
        self.readMemVal(d.addr, .bits64);
    self.xmm[d.xmm_dst] = source1;
    std.mem.writeInt(u64, self.xmm[d.xmm_dst][0..8], @bitCast(decoder.roundVexFloat(f64, @as(f64, @bitCast(source2_bits)), @truncate(d.imm))), .little);
    @memset(&self.ymm_hi[d.xmm_dst], 0);
}

pub fn executeVexRoundPackedF32(self: anytype, d: DecodedInsn) void {
    const source_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
    self.xmm[d.xmm_dst] = decoder.roundVexPackedF32(source_low, @truncate(d.imm));
    if (d.vector_256) {
        const source_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
        self.ymm_hi[d.xmm_dst] = decoder.roundVexPackedF32(source_high, @truncate(d.imm));
    } else {
        @memset(&self.ymm_hi[d.xmm_dst], 0);
    }
}

pub fn executeVexRoundPackedF64(self: anytype, d: DecodedInsn) void {
    const source_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
    self.xmm[d.xmm_dst] = decoder.roundVexPackedF64(source_low, @truncate(d.imm));
    if (d.vector_256) {
        const source_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
        self.ymm_hi[d.xmm_dst] = decoder.roundVexPackedF64(source_high, @truncate(d.imm));
    } else {
        @memset(&self.ymm_hi[d.xmm_dst], 0);
    }
}

pub fn executeVexFloatToSigned(self: anytype, d: DecodedInsn, comptime double: bool, comptime truncate: bool) void {
    if (double) {
        const source_bits: u64 = if (d.is_reg_form)
            std.mem.readInt(u64, self.xmm[d.xmm_src][0..8], .little)
        else
            self.readMemVal(d.addr, .bits64);
        const source: f64 = @bitCast(source_bits);
        self.setReg(d.dst_reg, d.size, decoder.convertVexFloatToSigned(f64, source, d.size, truncate));
    } else {
        const source_bits: u32 = if (d.is_reg_form)
            std.mem.readInt(u32, self.xmm[d.xmm_src][0..4], .little)
        else
            @truncate(self.readMemVal(d.addr, .bits32));
        const source: f32 = @bitCast(source_bits);
        self.setReg(d.dst_reg, d.size, decoder.convertVexFloatToSigned(f32, source, d.size, truncate));
    }
}

pub fn executeVexMoveMask(self: anytype, d: DecodedInsn) void {
    switch (d.op) {
        .pmovmskb, .vpmovmskb => {
            var mask: u32 = 0;
            for (self.xmm[d.xmm_src], 0..) |byte, index| {
                if (byte & 0x80 != 0) mask |= @as(u32, 1) << @intCast(index);
            }
            self.setReg(d.dst_reg, .bits32, mask);
        },
        .vpmovmskb_ymm => {
            var mask: u32 = 0;
            for (self.xmm[d.xmm_src], 0..) |byte, index| {
                if (byte & 0x80 != 0) mask |= @as(u32, 1) << @intCast(index);
            }
            for (self.ymm_hi[d.xmm_src], 0..) |byte, index| {
                if (byte & 0x80 != 0) mask |= @as(u32, 1) << @intCast(index + 16);
            }
            self.setReg(d.dst_reg, .bits32, mask);
        },
        .vmovmskps, .vmovmskpd => {
            const lane_bytes: usize = if (d.op == .vmovmskps) 4 else 8;
            const lanes_per_half = 16 / lane_bytes;
            const lane_count = if (d.vector_256) lanes_per_half * 2 else lanes_per_half;
            var mask: u32 = 0;
            for (0..lane_count) |lane| {
                const half = if (lane < lanes_per_half) self.xmm[d.xmm_src] else self.ymm_hi[d.xmm_src];
                const offset = (lane % lanes_per_half) * lane_bytes;
                const negative = if (lane_bytes == 4)
                    (std.mem.readInt(u32, half[offset..][0..4], .little) & 0x8000_0000) != 0
                else
                    (std.mem.readInt(u64, half[offset..][0..8], .little) & 0x8000_0000_0000_0000) != 0;
                if (negative) mask |= @as(u32, 1) << @intCast(lane);
            }
            self.setReg(d.dst_reg, .bits32, mask);
        },
        else => unreachable,
    }
}

fn vexSource128(self: anytype, d: DecodedInsn, source_index: u8, memory: bool, high: bool) [16]u8 {
    const offset: u64 = if (high) 16 else 0;
    if (memory) return self.readMem128(d.addr +% offset);
    return if (high) self.ymm_hi[source_index] else self.xmm[source_index];
}

pub fn executeVexPackedInteger(self: anytype, d: DecodedInsn, lane_bits: u8, operation: PackedIntegerOperation) void {
    const right_is_memory = !d.is_reg_form;
    self.xmm[d.xmm_dst] = packed_ops.packedIntegerBinary(
        vexSource128(self, d, d.xmm_src, false, false),
        vexSource128(self, d, d.xmm_src2, right_is_memory, false),
        lane_bits,
        operation,
    );
    if (d.vector_256) {
        self.ymm_hi[d.xmm_dst] = packed_ops.packedIntegerBinary(
            vexSource128(self, d, d.xmm_src, false, true),
            vexSource128(self, d, d.xmm_src2, right_is_memory, true),
            lane_bits,
            operation,
        );
    } else {
        @memset(&self.ymm_hi[d.xmm_dst], 0);
    }
}

pub fn executeVexPackedPack(self: anytype, d: DecodedInsn, operation: PackedPackOperation) void {
    const right_is_memory = !d.is_reg_form;
    self.xmm[d.xmm_dst] = packed_ops.packedIntegerPack(
        vexSource128(self, d, d.xmm_src, false, false),
        vexSource128(self, d, d.xmm_src2, right_is_memory, false),
        operation,
    );
    if (d.vector_256) {
        self.ymm_hi[d.xmm_dst] = packed_ops.packedIntegerPack(
            vexSource128(self, d, d.xmm_src, false, true),
            vexSource128(self, d, d.xmm_src2, right_is_memory, true),
            operation,
        );
    } else {
        @memset(&self.ymm_hi[d.xmm_dst], 0);
    }
}

pub fn executeVexPackedMinMax(self: anytype, d: DecodedInsn, kind: MinMaxKind) void {
    const right_is_memory = !d.is_reg_form;
    self.xmm[d.xmm_dst] = packed_ops.packedMinMax(
        vexSource128(self, d, d.xmm_src, false, false),
        vexSource128(self, d, d.xmm_src2, right_is_memory, false),
        kind,
    );
    if (d.vector_256) {
        self.ymm_hi[d.xmm_dst] = packed_ops.packedMinMax(
            vexSource128(self, d, d.xmm_src, false, true),
            vexSource128(self, d, d.xmm_src2, right_is_memory, true),
            kind,
        );
    } else {
        @memset(&self.ymm_hi[d.xmm_dst], 0);
    }
}

pub fn executeVexPackedMulHigh(self: anytype, d: DecodedInsn, signed: bool) void {
    const right_is_memory = !d.is_reg_form;
    self.xmm[d.xmm_dst] = packed_ops.packedIntegerMulHigh(
        vexSource128(self, d, d.xmm_src, false, false),
        vexSource128(self, d, d.xmm_src2, right_is_memory, false),
        signed,
    );
    if (d.vector_256) {
        self.ymm_hi[d.xmm_dst] = packed_ops.packedIntegerMulHigh(
            vexSource128(self, d, d.xmm_src, false, true),
            vexSource128(self, d, d.xmm_src2, right_is_memory, true),
            signed,
        );
    } else {
        @memset(&self.ymm_hi[d.xmm_dst], 0);
    }
}

pub fn executeVexMultiplyUnsignedEvenDwords(self: anytype, d: DecodedInsn) void {
    const right_is_memory = !d.is_reg_form;
    self.xmm[d.xmm_dst] = packed_ops.multiplyUnsignedEvenDwords(
        vexSource128(self, d, d.xmm_src, false, false),
        vexSource128(self, d, d.xmm_src2, right_is_memory, false),
    );
    if (d.vector_256) {
        self.ymm_hi[d.xmm_dst] = packed_ops.multiplyUnsignedEvenDwords(
            vexSource128(self, d, d.xmm_src, false, true),
            vexSource128(self, d, d.xmm_src2, right_is_memory, true),
        );
    } else {
        @memset(&self.ymm_hi[d.xmm_dst], 0);
    }
}

pub fn executeVexBlendWords(self: anytype, d: DecodedInsn) void {
    const right_is_memory = !d.is_reg_form;
    self.xmm[d.xmm_dst] = packed_ops.blendPackedWords(
        vexSource128(self, d, d.xmm_src, false, false),
        vexSource128(self, d, d.xmm_src2, right_is_memory, false),
        @truncate(d.imm),
    );
    if (d.vector_256) {
        self.ymm_hi[d.xmm_dst] = packed_ops.blendPackedWords(
            vexSource128(self, d, d.xmm_src, false, true),
            vexSource128(self, d, d.xmm_src2, right_is_memory, true),
            @truncate(d.imm),
        );
    } else {
        @memset(&self.ymm_hi[d.xmm_dst], 0);
    }
}

pub fn executeVexBlendVariable(self: anytype, d: DecodedInsn, lane_bits: u8) void {
    const right_is_memory = !d.is_reg_form;
    self.xmm[d.xmm_dst] = packed_ops.blendPackedElements(
        vexSource128(self, d, d.xmm_src, false, false),
        vexSource128(self, d, d.xmm_src2, right_is_memory, false),
        self.xmm[d.xmm_mask],
        lane_bits,
    );
    if (d.vector_256) {
        self.ymm_hi[d.xmm_dst] = packed_ops.blendPackedElements(
            vexSource128(self, d, d.xmm_src, false, true),
            vexSource128(self, d, d.xmm_src2, right_is_memory, true),
            self.ymm_hi[d.xmm_mask],
            lane_bits,
        );
    } else {
        @memset(&self.ymm_hi[d.xmm_dst], 0);
    }
}

pub fn executeVexPackedShift(self: anytype, d: DecodedInsn, lane_bits: u8, left: bool, arithmetic: bool, whole_bytes: bool) void {
    const source_low = vexSource128(self, d, d.xmm_src, !d.is_reg_form, false);
    const shift = if (whole_bytes)
        packed_ops.shiftPackedBytes(source_low, d.imm, left)
    else if (arithmetic)
        packed_ops.arithmeticShiftPackedElements(source_low, lane_bits, d.imm)
    else
        packed_ops.shiftPackedElements(source_low, lane_bits, d.imm, left);
    self.xmm[d.xmm_dst] = shift;
    if (d.vector_256) {
        const source_high = vexSource128(self, d, d.xmm_src, !d.is_reg_form, true);
        self.ymm_hi[d.xmm_dst] = if (whole_bytes)
            packed_ops.shiftPackedBytes(source_high, d.imm, left)
        else if (arithmetic)
            packed_ops.arithmeticShiftPackedElements(source_high, lane_bits, d.imm)
        else
            packed_ops.shiftPackedElements(source_high, lane_bits, d.imm, left);
    } else {
        @memset(&self.ymm_hi[d.xmm_dst], 0);
    }
}
