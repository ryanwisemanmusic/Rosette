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
const VexArithmetic = @import("decoder.zig").VexArithmetic;
const VexBitwise = @import("decoder.zig").VexBitwise;
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

pub fn executeFucomip(self: anytype, source: u3) void {
    const lhs = self.x87.get(0) orelse return;
    const rhs = self.x87.get(source) orelse return;
    self.regs.rflags &= ~(RFL_ZF | RFL_PF | RFL_CF);
    if (std.math.isNan(lhs) or std.math.isNan(rhs)) {
        self.regs.rflags |= RFL_ZF | RFL_PF | RFL_CF;
    } else if (lhs < rhs) {
        self.regs.rflags |= RFL_CF;
    } else if (lhs == rhs) {
        self.regs.rflags |= RFL_ZF;
    }
    _ = self.x87.pop();
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
    @memset(&self.ymm_hi[d.xmm_dst], 0);
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
    @memset(&self.ymm_hi[d.xmm_dst], 0);
}

pub fn executeVexPackedF32(self: anytype, d: DecodedInsn, operation: VexArithmetic) void {
    const source1_low = self.xmm[d.xmm_src];
    const source2_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
    self.xmm[d.xmm_dst] = applyVexPackedF32(source1_low, source2_low, operation);

    if (d.vector_256) {
        const source1_high = self.ymm_hi[d.xmm_src];
        const source2_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
        self.ymm_hi[d.xmm_dst] = applyVexPackedF32(source1_high, source2_high, operation);
    } else {
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
    } else {
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
    @memset(&self.ymm_hi[d.xmm_dst], 0);
}

pub fn executeVexSqrtScalarF64(self: anytype, d: DecodedInsn) void {
    const source_bits = if (d.is_reg_form)
        std.mem.readInt(u64, self.xmm[d.xmm_src2][0..8], .little)
    else
        self.readMemVal(d.addr, .bits64);
    const source_value: f64 = @bitCast(source_bits);

    self.xmm[d.xmm_dst] = self.xmm[d.xmm_src];
    std.mem.writeInt(u64, self.xmm[d.xmm_dst][0..8], @bitCast(@sqrt(source_value)), .little);
    @memset(&self.ymm_hi[d.xmm_dst], 0);
}

pub fn executeVexSqrtPackedF32(self: anytype, d: DecodedInsn) void {
    const source_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
    self.xmm[d.xmm_dst] = sqrtVexPackedF32(source_low);
    if (d.vector_256) {
        const source_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
        self.ymm_hi[d.xmm_dst] = sqrtVexPackedF32(source_high);
    } else {
        @memset(&self.ymm_hi[d.xmm_dst], 0);
    }
}

pub fn executeVexSqrtPackedF64(self: anytype, d: DecodedInsn) void {
    const source_low = if (d.is_reg_form) self.xmm[d.xmm_src2] else self.readMem128(d.addr);
    self.xmm[d.xmm_dst] = sqrtVexPackedF64(source_low);
    if (d.vector_256) {
        const source_high = if (d.is_reg_form) self.ymm_hi[d.xmm_src2] else self.readMem128(d.addr + 16);
        self.ymm_hi[d.xmm_dst] = sqrtVexPackedF64(source_high);
    } else {
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
    } else {
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
    } else {
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
    const mask: Lane = if (predicate.evaluate(left, right)) ~@as(Lane, 0) else 0;
    std.mem.writeInt(Lane, self.xmm[d.xmm_dst][0..width], mask, .little);
    @memset(&self.ymm_hi[d.xmm_dst], 0);
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
