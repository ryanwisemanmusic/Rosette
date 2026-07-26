const std = @import("std");
const types = @import("types.zig");
const wide = @import("wide.zig");

pub fn executeUnary(comptime bits: usize, meta: types.InstructionMeta, src: wide.Wide(bits), features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    try types.validateMeta(meta);
    try types.requireFeature(meta, features);
    try types.requireWidth(meta, bits);
    return switch (meta.operation) {
        .sqrt_ps => wide.mapUnary(bits, f32, src, .sqrt),
        .sqrt_pd => wide.mapUnary(bits, f64, src, .sqrt),
        .cvt_pd2ps => wide.cvtF64ToF32(bits, src),
        .cvt_ps2pd => wide.cvtF32ToF64(bits, src),
        .cvt_dq2ps => wide.cvtS32ToF32(bits, src),
        .cvt_ps2dq => wide.cvtF32ToS32(bits, src),
        .cvtt_ps2dq => wide.cvtF32ToS32Trunc(bits, src),
        .pabs => executeAbsValue(bits, meta, src),
        .pnot => executeBitwiseNot(bits, meta, src),
        .round_to_int => executeRoundToInt(bits, meta, src),
        .compress_ps => executeCompressFloat(bits, meta, src, f32),
        .compress_pd => executeCompressFloat(bits, meta, src, f64),
        .expand_ps => executeExpandFloat(bits, meta, src, f32),
        .expand_pd => executeExpandFloat(bits, meta, src, f64),
        .cvt_pd2dq => wide.cvtPd2Dq(bits, src),
        .cvtt_pd2dq => wide.cvttPd2Dq(bits, src),
        .cvt_dq2pd => wide.cvtDq2Pd(bits, src),
        .cvt_ph2ps => wide.cvtF16ToF32(bits, src),
        .cvt_ps2ph => wide.cvtF32ToF16(bits, src),
        .cvt_bf16 => wide.cvtF32ToBF16(bits, src),
        else => types.SafetyError.UnsupportedInstructionWidth,
    };
}

pub fn executeUnaryMasked(comptime bits: usize, meta: types.InstructionMeta, merge: wide.Wide(bits), src: wide.Wide(bits), mask: u64, mode: wide.MaskMode, features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    try types.validateMeta(meta);
    try types.requireFeature(meta, features);
    try types.requireWidth(meta, bits);
    if (!meta.supports_masking) return types.SafetyError.UnsupportedInstructionWidth;
    return switch (meta.operation) {
        .sqrt_ps => wide.mapUnaryMasked(bits, f32, merge, src, mask, mode, .sqrt),
        .sqrt_pd => wide.mapUnaryMasked(bits, f64, merge, src, mask, mode, .sqrt),
        .cvt_pd2ps => {
            const computed = wide.cvtF64ToF32(bits, src);
            return wide.applyLaneMask(bits, f32, merge, computed, mask, mode);
        },
        .cvt_ps2pd => {
            const computed = wide.cvtF32ToF64(bits, src);
            return wide.applyLaneMask(bits, f64, merge, computed, mask, mode);
        },
        .cvt_dq2ps => {
            const computed = wide.cvtS32ToF32(bits, src);
            return wide.applyLaneMask(bits, f32, merge, computed, mask, mode);
        },
        .cvt_ps2dq => {
            const computed = wide.cvtF32ToS32(bits, src);
            return wide.applyLaneMask(bits, i32, merge, computed, mask, mode);
        },
        .cvtt_ps2dq => {
            const computed = wide.cvtF32ToS32Trunc(bits, src);
            return wide.applyLaneMask(bits, i32, merge, computed, mask, mode);
        },
        .pabs => executeAbsValueMasked(bits, meta, merge, src, mask, mode),
        .pnot => executeBitwiseNotMasked(bits, meta, merge, src, mask, mode),
        .cvt_pd2dq => {
            const computed = wide.cvtPd2Dq(bits, src);
            return wide.applyLaneMask(bits, i32, merge, computed, mask, mode);
        },
        .cvtt_pd2dq => {
            const computed = wide.cvttPd2Dq(bits, src);
            return wide.applyLaneMask(bits, i32, merge, computed, mask, mode);
        },
        .cvt_dq2pd => {
            const computed = wide.cvtDq2Pd(bits, src);
            return wide.applyLaneMask(bits, f64, merge, computed, mask, mode);
        },
        .cvt_ph2ps => {
            const computed = wide.cvtF16ToF32(bits, src);
            return wide.applyLaneMask(bits, f32, merge, computed, mask, mode);
        },
        .cvt_ps2ph => {
            const computed = wide.cvtF32ToF16(bits, src);
            return wide.applyLaneMask(bits, u32, merge, computed, mask, mode);
        },
        .cvt_bf16 => {
            const computed = wide.cvtF32ToBF16(bits, src);
            return wide.applyLaneMask(bits, u32, merge, computed, mask, mode);
        },
        else => types.SafetyError.UnsupportedInstructionWidth,
    };
}

pub fn executeBinary(comptime bits: usize, meta: types.InstructionMeta, lhs: wide.Wide(bits), rhs: wide.Wide(bits), features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    try types.validateMeta(meta);
    try types.requireFeature(meta, features);
    try types.requireWidth(meta, bits);
    return switch (meta.operation) {
        .add_ps => wide.mapBinary(bits, f32, lhs, rhs, .add),
        .add_pd => wide.mapBinary(bits, f64, lhs, rhs, .add),
        .sub_ps => wide.mapBinary(bits, f32, lhs, rhs, .sub),
        .sub_pd => wide.mapBinary(bits, f64, lhs, rhs, .sub),
        .mul_ps => wide.mapBinary(bits, f32, lhs, rhs, .mul),
        .mul_pd => wide.mapBinary(bits, f64, lhs, rhs, .mul),
        .div_ps => wide.mapBinary(bits, f32, lhs, rhs, .div),
        .div_pd => wide.mapBinary(bits, f64, lhs, rhs, .div),
        .addsub_ps => wide.mapBinary(bits, f32, lhs, rhs, .addsub),
        .addsub_pd => wide.mapBinary(bits, f64, lhs, rhs, .addsub),
        .or_ps => wide.mapBinary(bits, u32, lhs, rhs, .bit_or),
        .or_pd => wide.mapBinary(bits, u64, lhs, rhs, .bit_or),
        .xor_ps => wide.mapBinary(bits, u32, lhs, rhs, .bit_xor),
        .xor_pd => wide.mapBinary(bits, u64, lhs, rhs, .bit_xor),
        .and_ps => wide.mapBinary(bits, u32, lhs, rhs, .bit_and),
        .and_pd => wide.mapBinary(bits, u64, lhs, rhs, .bit_and),
        .andn_ps => wide.mapBinary(bits, u32, lhs, rhs, .bit_andnot),
        .andn_pd => wide.mapBinary(bits, u64, lhs, rhs, .bit_andnot),
        .cmp_ps => wide.mapBinary(bits, f32, lhs, rhs, .cmp),
        .cmp_pd => wide.mapBinary(bits, f64, lhs, rhs, .cmp),
        .blend_ps => blk: {
            std.debug.print("cleo: {s} called via execute() with imm=0 (did you mean executeImmediate?)\n", .{@tagName(meta.operation)});
            break :blk wide.blendImmediate(bits, u32, lhs, rhs, 0);
        },
        .blend_pd => blk: {
            std.debug.print("cleo: {s} called via execute() with imm=0 (did you mean executeImmediate?)\n", .{@tagName(meta.operation)});
            break :blk wide.blendImmediate(bits, u64, lhs, rhs, 0);
        },
        .shuf_ps => blk: {
            std.debug.print("cleo: {s} called via execute() with imm=0 (did you mean executeImmediate?)\n", .{@tagName(meta.operation)});
            break :blk wide.shuffleImmediatePS(bits, lhs, rhs, 0);
        },
        .shuf_pd => blk: {
            std.debug.print("cleo: {s} called via execute() with imm=0 (did you mean executeImmediate?)\n", .{@tagName(meta.operation)});
            break :blk wide.shuffleImmediatePD(bits, lhs, rhs, 0);
        },
        .dpps => blk: {
            std.debug.print("cleo: {s} called via execute() with imm=0 (did you mean executeImmediate?)\n", .{@tagName(meta.operation)});
            break :blk wide.dotProductPS(bits, lhs, rhs, 0);
        },
        .aesenc => wide.aesRound(bits, lhs, rhs, .enc),
        .aesdec => wide.aesRound(bits, lhs, rhs, .dec),
        .aesenclast => wide.aesRound(bits, lhs, rhs, .enc_last),
        .aesdeclast => wide.aesRound(bits, lhs, rhs, .dec_last),
        .pmin_signed => executeIntegerMinMax(bits, meta, lhs, rhs, true, .min),
        .pmin_unsigned => executeIntegerMinMax(bits, meta, lhs, rhs, false, .min),
        .pmax_signed => executeIntegerMinMax(bits, meta, lhs, rhs, true, .max),
        .pmax_unsigned => executeIntegerMinMax(bits, meta, lhs, rhs, false, .max),
        .padd => executeIntegerBinary(bits, meta, lhs, rhs, .add),
        .psub => executeIntegerBinary(bits, meta, lhs, rhs, .sub),
        .pcmpeq => executeIntegerBinary(bits, meta, lhs, rhs, .cmp),
        .pcmpgt => executeIntegerBinary(bits, meta, lhs, rhs, .cmpgt),
        .pmull => executeIntegerBinary(bits, meta, lhs, rhs, .mul),
        .psubs => executeIntegerBinary(bits, meta, lhs, rhs, .subs),
        .psubus => executeIntegerBinary(bits, meta, lhs, rhs, .subus),
        .psll => executeShiftByVector(bits, meta, lhs, rhs, .shift_left),
        .psra => executeShiftByVector(bits, meta, lhs, rhs, .shift_right_arith),
        .psrl => executeShiftByVector(bits, meta, lhs, rhs, .shift_right_logical),
        .packss => executePack(bits, meta, lhs, rhs, .signed_saturate),
        .packus => executePack(bits, meta, lhs, rhs, .unsigned_saturate),
        .psign => executeSignOperation(bits, meta, lhs, rhs),
        .unpck_low => executeUnpackLow(bits, meta, lhs, rhs),
        .unpck_high => executeUnpackHigh(bits, meta, lhs, rhs),
        .avg => executeAverage(bits, meta, lhs, rhs),
        .rotate_left_variable => executeRotateVariable(bits, meta, lhs, rhs, .left),
        .rotate_right_variable => executeRotateVariable(bits, meta, lhs, rhs, .right),
        .gf2p8_mul => executeGf2p8Mul(bits, meta, lhs, rhs),
        .sha1_msg1 => executeShaOp(bits, meta, lhs, rhs, .msg1),
        .sha1_msg2 => executeShaOp(bits, meta, lhs, rhs, .msg2),
        .sha1_nexte => executeShaOp(bits, meta, lhs, rhs, .nexte),
        .sha256_msg1 => executeShaOp(bits, meta, lhs, rhs, .sha256_msg1),
        .sha256_msg2 => executeShaOp(bits, meta, lhs, rhs, .sha256_msg2),
        .sha256_rnds2 => executeShaOp(bits, meta, lhs, rhs, .sha256_rnds2),
        .scale_ps => executeScaleFloat(bits, meta, lhs, rhs, f32),
        .scale_pd => executeScaleFloat(bits, meta, lhs, rhs, f64),
        .permute_d => {
            const result = wide.permuteDWord(bits, lhs, rhs);
            return result;
        },
        .permute_q => {
            const result = wide.permuteQWord(bits, lhs, rhs);
            return result;
        },
        // GATHER/SCATTER — indexed memory access (stubs: identity pass-through)
        .gather_ps, .gather_pd, .gather_d, .gather_q, .scatter_ps, .scatter_pd, .scatter_d, .scatter_q => lhs,
        else => types.SafetyError.UnsupportedInstructionWidth,
    };
}

fn executeIntegerBinary(comptime bits: usize, meta: types.InstructionMeta, lhs: wide.Wide(bits), rhs: wide.Wide(bits), comptime op: wide.BinaryOp) types.SafetyError!wide.Wide(bits) {
    return switch (meta.element_bits) {
        8 => wide.mapBinary(bits, i8, lhs, rhs, op),
        16 => wide.mapBinary(bits, i16, lhs, rhs, op),
        32 => wide.mapBinary(bits, i32, lhs, rhs, op),
        64 => wide.mapBinary(bits, i64, lhs, rhs, op),
        else => types.SafetyError.InvalidElementWidth,
    };
}

fn executeIntegerMinMax(comptime bits: usize, meta: types.InstructionMeta, lhs: wide.Wide(bits), rhs: wide.Wide(bits), comptime signed: bool, comptime op: wide.BinaryOp) types.SafetyError!wide.Wide(bits) {
    return switch (meta.element_bits) {
        8 => if (signed) wide.mapBinary(bits, i8, lhs, rhs, op) else wide.mapBinary(bits, u8, lhs, rhs, op),
        16 => if (signed) wide.mapBinary(bits, i16, lhs, rhs, op) else wide.mapBinary(bits, u16, lhs, rhs, op),
        32 => if (signed) wide.mapBinary(bits, i32, lhs, rhs, op) else wide.mapBinary(bits, u32, lhs, rhs, op),
        64 => if (signed) wide.mapBinary(bits, i64, lhs, rhs, op) else wide.mapBinary(bits, u64, lhs, rhs, op),
        else => types.SafetyError.InvalidElementWidth,
    };
}

pub fn executeBinaryImmediate(comptime bits: usize, meta: types.InstructionMeta, lhs: wide.Wide(bits), rhs: wide.Wide(bits), immediate: u8, features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    try types.validateMeta(meta);
    try types.requireFeature(meta, features);
    try types.requireWidth(meta, bits);
    return switch (meta.operation) {
        .cmp_ps => wide.cmpImmediatePS(bits, lhs, rhs, immediate),
        .cmp_pd => wide.cmpImmediatePD(bits, lhs, rhs, immediate),
        .blend_ps => wide.blendImmediate(bits, u32, lhs, rhs, immediate),
        .blend_pd => wide.blendImmediate(bits, u64, lhs, rhs, immediate),
        .shuf_ps => wide.shuffleImmediatePS(bits, lhs, rhs, immediate),
        .shuf_pd => wide.shuffleImmediatePD(bits, lhs, rhs, immediate),
        .dpps => wide.dotProductPS(bits, lhs, rhs, immediate),
        .insert_block => blk: {
            // For element_bits=256 (F32x8/F64x4/I32x8/I64x4), the immediate
            // selects 256-bit block positions, which map to 2× 128-bit blocks.
            const block_ratio = @max(meta.element_bits, 128) / 128;
            break :blk wide.insertBlock(bits, lhs, rhs, (immediate & 0x0F) * @as(usize, block_ratio));
        },
        .insert_element => blk: {
            const lane = immediate & 0x0F;
            break :blk executeInsertElement(bits, meta, lhs, rhs, lane);
        },
        .insert_ps => executeInsertPS(bits, meta, lhs, rhs, immediate),
        .@"align" => executeAlign(bits, meta, lhs, rhs, immediate),
        .rotate_left => executeRotateImmediate(bits, meta, lhs, rhs, immediate, .left),
        .rotate_right => executeRotateImmediate(bits, meta, lhs, rhs, immediate, .right),
        .ternary_logic => executeTernaryLogic(bits, meta, lhs, rhs, immediate),
        .gf2p8_affine => executeGf2p8Affine(bits, meta, lhs, rhs, immediate),
        .gf2p8_affine_inv => executeGf2p8AffineInv(bits, meta, lhs, rhs, immediate),
        .sha1_rnds4 => executeShaRnds4(bits, meta, lhs, rhs, immediate),
        .range_ps => executeRangeFloat(bits, meta, lhs, rhs, immediate, f32),
        .range_pd => executeRangeFloat(bits, meta, lhs, rhs, immediate, f64),
        .fixup_ps => executeFixupFloat(bits, meta, lhs, rhs, immediate, f32),
        .fixup_pd => executeFixupFloat(bits, meta, lhs, rhs, immediate, f64),
        .permil => executePermil(bits, meta, lhs, rhs, immediate),
        .byte_shift_left => {
            const result = wide.byteShiftLeft(bits, lhs, immediate);
            return result;
        },
        .byte_shift_right => {
            const result = wide.byteShiftRight(bits, lhs, immediate);
            return result;
        },
        else => types.SafetyError.UnsupportedInstructionWidth,
    };
}

pub fn executeBlendVariable(comptime bits: usize, meta: types.InstructionMeta, lhs: wide.Wide(bits), rhs: wide.Wide(bits), selector: wide.Wide(bits), features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    try types.validateMeta(meta);
    try types.requireFeature(meta, features);
    try types.requireWidth(meta, bits);
    return switch (meta.operation) {
        .blendv_ps => wide.blendVariable(bits, u32, lhs, rhs, selector),
        .blendv_pd => wide.blendVariable(bits, u64, lhs, rhs, selector),
        else => types.SafetyError.UnsupportedInstructionWidth,
    };
}

pub fn executeAccumulate(comptime bits: usize, meta: types.InstructionMeta, accum: wide.Wide(bits), lhs: wide.Wide(bits), rhs: wide.Wide(bits), features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    try types.validateMeta(meta);
    try types.requireFeature(meta, features);
    try types.requireWidth(meta, bits);
    return switch (meta.operation) {
        .two_source_permute => executeTwoSourcePermute(bits, meta, lhs, accum, rhs),
        .vdpbf16ps => wide.dotBF16PS(bits, accum, lhs, rhs),
        .fma_ps => blk: {
            const prod = wide.mapBinary(bits, f32, lhs, rhs, .mul);
            break :blk wide.mapBinary(bits, f32, accum, prod, .add);
        },
        .fma_pd => blk: {
            const prod = wide.mapBinary(bits, f64, lhs, rhs, .mul);
            break :blk wide.mapBinary(bits, f64, accum, prod, .add);
        },
        .fms_ps => blk: {
            const prod = wide.mapBinary(bits, f32, lhs, rhs, .mul);
            break :blk wide.mapBinary(bits, f32, prod, accum, .sub);
        },
        .fms_pd => blk: {
            const prod = wide.mapBinary(bits, f64, lhs, rhs, .mul);
            break :blk wide.mapBinary(bits, f64, prod, accum, .sub);
        },
        .fnma_ps => blk: {
            const prod = wide.mapBinary(bits, f32, lhs, rhs, .mul);
            break :blk wide.mapBinary(bits, f32, accum, prod, .sub);
        },
        .fnma_pd => blk: {
            const prod = wide.mapBinary(bits, f64, lhs, rhs, .mul);
            break :blk wide.mapBinary(bits, f64, accum, prod, .sub);
        },
        .fnms_ps => blk: {
            const prod = wide.mapBinary(bits, f32, lhs, rhs, .mul);
            const sum = wide.mapBinary(bits, f32, prod, accum, .add);
            const zero = wide.Wide(bits).zero();
            break :blk wide.mapBinary(bits, f32, zero, sum, .sub);
        },
        .fnms_pd => blk: {
            const prod = wide.mapBinary(bits, f64, lhs, rhs, .mul);
            const sum = wide.mapBinary(bits, f64, prod, accum, .add);
            const zero = wide.Wide(bits).zero();
            break :blk wide.mapBinary(bits, f64, zero, sum, .sub);
        },
        .fma_addsub_ps => blk: {
            const prod = wide.mapBinary(bits, f32, lhs, rhs, .mul);
            break :blk wide.mapBinary(bits, f32, prod, accum, .addsub);
        },
        .fma_addsub_pd => blk: {
            const prod = wide.mapBinary(bits, f64, lhs, rhs, .mul);
            break :blk wide.mapBinary(bits, f64, prod, accum, .addsub);
        },
        .fma_subadd_ps => blk: {
            const prod = wide.mapBinary(bits, f32, lhs, rhs, .mul);
            const lanes = comptime wide.laneCount(bits, f32);
            var result: [lanes]f32 = undefined;
            const acc_arr = wide.toArray(bits, f32, accum);
            const prod_arr = wide.toArray(bits, f32, prod);
            for (0..lanes) |lane| {
                result[lane] = if ((lane & 1) == 0) acc_arr[lane] + prod_arr[lane] else acc_arr[lane] - prod_arr[lane];
            }
            break :blk wide.fromArray(bits, f32, result);
        },
        .fma_subadd_pd => blk: {
            const prod = wide.mapBinary(bits, f64, lhs, rhs, .mul);
            const lanes = comptime wide.laneCount(bits, f64);
            var result: [lanes]f64 = undefined;
            const acc_arr = wide.toArray(bits, f64, accum);
            const prod_arr = wide.toArray(bits, f64, prod);
            for (0..lanes) |lane| {
                result[lane] = if ((lane & 1) == 0) acc_arr[lane] + prod_arr[lane] else acc_arr[lane] - prod_arr[lane];
            }
            break :blk wide.fromArray(bits, f64, result);
        },
        else => types.SafetyError.UnsupportedInstructionWidth,
    };
}

pub fn executeBinaryMasked(comptime bits: usize, meta: types.InstructionMeta, merge: wide.Wide(bits), lhs: wide.Wide(bits), rhs: wide.Wide(bits), mask: u64, mode: wide.MaskMode, features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    try types.validateMeta(meta);
    try types.requireFeature(meta, features);
    try types.requireWidth(meta, bits);
    if (!meta.supports_masking) return types.SafetyError.UnsupportedInstructionWidth;
    return switch (meta.operation) {
        .add_ps => wide.mapBinaryMasked(bits, f32, merge, lhs, rhs, mask, mode, .add),
        .add_pd => wide.mapBinaryMasked(bits, f64, merge, lhs, rhs, mask, mode, .add),
        .sub_ps => wide.mapBinaryMasked(bits, f32, merge, lhs, rhs, mask, mode, .sub),
        .sub_pd => wide.mapBinaryMasked(bits, f64, merge, lhs, rhs, mask, mode, .sub),
        .mul_ps => wide.mapBinaryMasked(bits, f32, merge, lhs, rhs, mask, mode, .mul),
        .mul_pd => wide.mapBinaryMasked(bits, f64, merge, lhs, rhs, mask, mode, .mul),
        .div_ps => wide.mapBinaryMasked(bits, f32, merge, lhs, rhs, mask, mode, .div),
        .div_pd => wide.mapBinaryMasked(bits, f64, merge, lhs, rhs, mask, mode, .div),
        .or_ps => wide.mapBinaryMasked(bits, u32, merge, lhs, rhs, mask, mode, .bit_or),
        .or_pd => wide.mapBinaryMasked(bits, u64, merge, lhs, rhs, mask, mode, .bit_or),
        .xor_ps => wide.mapBinaryMasked(bits, u32, merge, lhs, rhs, mask, mode, .bit_xor),
        .xor_pd => wide.mapBinaryMasked(bits, u64, merge, lhs, rhs, mask, mode, .bit_xor),
        .and_ps => wide.mapBinaryMasked(bits, u32, merge, lhs, rhs, mask, mode, .bit_and),
        .and_pd => wide.mapBinaryMasked(bits, u64, merge, lhs, rhs, mask, mode, .bit_and),
        .andn_ps => wide.mapBinaryMasked(bits, u32, merge, lhs, rhs, mask, mode, .bit_andnot),
        .andn_pd => wide.mapBinaryMasked(bits, u64, merge, lhs, rhs, mask, mode, .bit_andnot),
        .cmp_ps => wide.mapBinaryMasked(bits, f32, merge, lhs, rhs, mask, mode, .cmp),
        .cmp_pd => wide.mapBinaryMasked(bits, f64, merge, lhs, rhs, mask, mode, .cmp),
        .shuf_ps => wide.shuffleImmediatePSMasked(bits, merge, lhs, rhs, 0, mask, mode),
        .shuf_pd => wide.shuffleImmediatePDMasked(bits, merge, lhs, rhs, 0, mask, mode),
        .pmin_signed => executeIntegerMinMaxMasked(bits, meta, merge, lhs, rhs, mask, mode, true, .min),
        .pmin_unsigned => executeIntegerMinMaxMasked(bits, meta, merge, lhs, rhs, mask, mode, false, .min),
        .pmax_signed => executeIntegerMinMaxMasked(bits, meta, merge, lhs, rhs, mask, mode, true, .max),
        .pmax_unsigned => executeIntegerMinMaxMasked(bits, meta, merge, lhs, rhs, mask, mode, false, .max),
        .padd => executeIntegerBinaryMasked(bits, meta, merge, lhs, rhs, mask, mode, .add),
        .psub => executeIntegerBinaryMasked(bits, meta, merge, lhs, rhs, mask, mode, .sub),
        .pcmpeq => executeIntegerBinaryMasked(bits, meta, merge, lhs, rhs, mask, mode, .cmp),
        .pcmpgt => executeIntegerBinaryMasked(bits, meta, merge, lhs, rhs, mask, mode, .cmpgt),
        .pmull => executeIntegerBinaryMasked(bits, meta, merge, lhs, rhs, mask, mode, .mul),
        .psubs => executeIntegerBinaryMasked(bits, meta, merge, lhs, rhs, mask, mode, .subs),
        .psubus => executeIntegerBinaryMasked(bits, meta, merge, lhs, rhs, mask, mode, .subus),
        .psign => executeSignOperationMasked(bits, meta, merge, lhs, rhs, mask, mode),
        .unpck_low => executeUnpackLowMasked(bits, meta, merge, lhs, rhs, mask, mode),
        .unpck_high => executeUnpackHighMasked(bits, meta, merge, lhs, rhs, mask, mode),
        else => types.SafetyError.UnsupportedInstructionWidth,
    };
}

fn executeIntegerBinaryMasked(comptime bits: usize, meta: types.InstructionMeta, merge: wide.Wide(bits), lhs: wide.Wide(bits), rhs: wide.Wide(bits), mask: u64, mode: wide.MaskMode, comptime op: wide.BinaryOp) types.SafetyError!wide.Wide(bits) {
    return switch (meta.element_bits) {
        8 => wide.mapBinaryMasked(bits, i8, merge, lhs, rhs, mask, mode, op),
        16 => wide.mapBinaryMasked(bits, i16, merge, lhs, rhs, mask, mode, op),
        32 => wide.mapBinaryMasked(bits, i32, merge, lhs, rhs, mask, mode, op),
        64 => wide.mapBinaryMasked(bits, i64, merge, lhs, rhs, mask, mode, op),
        else => types.SafetyError.InvalidElementWidth,
    };
}

fn executeIntegerMinMaxMasked(comptime bits: usize, meta: types.InstructionMeta, merge: wide.Wide(bits), lhs: wide.Wide(bits), rhs: wide.Wide(bits), mask: u64, mode: wide.MaskMode, comptime signed: bool, comptime op: wide.BinaryOp) types.SafetyError!wide.Wide(bits) {
    return switch (meta.element_bits) {
        8 => if (signed) wide.mapBinaryMasked(bits, i8, merge, lhs, rhs, mask, mode, op) else wide.mapBinaryMasked(bits, u8, merge, lhs, rhs, mask, mode, op),
        16 => if (signed) wide.mapBinaryMasked(bits, i16, merge, lhs, rhs, mask, mode, op) else wide.mapBinaryMasked(bits, u16, merge, lhs, rhs, mask, mode, op),
        32 => if (signed) wide.mapBinaryMasked(bits, i32, merge, lhs, rhs, mask, mode, op) else wide.mapBinaryMasked(bits, u32, merge, lhs, rhs, mask, mode, op),
        64 => if (signed) wide.mapBinaryMasked(bits, i64, merge, lhs, rhs, mask, mode, op) else wide.mapBinaryMasked(bits, u64, merge, lhs, rhs, mask, mode, op),
        else => types.SafetyError.InvalidElementWidth,
    };
}

pub fn executeBinaryMaskedImmediate(comptime bits: usize, meta: types.InstructionMeta, merge: wide.Wide(bits), lhs: wide.Wide(bits), rhs: wide.Wide(bits), immediate: u8, mask: u64, mode: wide.MaskMode, features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    try types.validateMeta(meta);
    try types.requireFeature(meta, features);
    try types.requireWidth(meta, bits);
    if (!meta.supports_masking) return types.SafetyError.UnsupportedInstructionWidth;
    return switch (meta.operation) {
        .cmp_ps => wide.cmpImmediatePSMasked(bits, merge, lhs, rhs, immediate, mask, mode),
        .cmp_pd => wide.cmpImmediatePDMasked(bits, merge, lhs, rhs, immediate, mask, mode),
        .shuf_ps => wide.shuffleImmediatePSMasked(bits, merge, lhs, rhs, immediate, mask, mode),
        .shuf_pd => wide.shuffleImmediatePDMasked(bits, merge, lhs, rhs, immediate, mask, mode),
        .rotate_left => blk: {
            const computed = try executeRotateImmediate(bits, meta, lhs, rhs, immediate, .left);
            break :blk switch (meta.element_bits) {
                32 => wide.applyLaneMask(bits, u32, merge, computed, mask, mode),
                64 => wide.applyLaneMask(bits, u64, merge, computed, mask, mode),
                else => types.SafetyError.InvalidElementWidth,
            };
        },
        .rotate_right => blk: {
            const computed = try executeRotateImmediate(bits, meta, lhs, rhs, immediate, .right);
            break :blk switch (meta.element_bits) {
                32 => wide.applyLaneMask(bits, u32, merge, computed, mask, mode),
                64 => wide.applyLaneMask(bits, u64, merge, computed, mask, mode),
                else => types.SafetyError.InvalidElementWidth,
            };
        },
        else => types.SafetyError.UnsupportedInstructionWidth,
    };
}

pub fn executeAccumulateMasked(comptime bits: usize, meta: types.InstructionMeta, merge: wide.Wide(bits), accum: wide.Wide(bits), lhs: wide.Wide(bits), rhs: wide.Wide(bits), mask: u64, mode: wide.MaskMode, features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    try types.validateMeta(meta);
    try types.requireFeature(meta, features);
    try types.requireWidth(meta, bits);
    if (!meta.supports_masking) return types.SafetyError.UnsupportedInstructionWidth;
    return switch (meta.operation) {
        .vdpbf16ps => wide.dotBF16PSMasked(bits, merge, accum, lhs, rhs, mask, mode),
        .fma_ps => {
            const computed = try executeAccumulate(bits, meta, accum, lhs, rhs, features);
            return wide.applyLaneMask(bits, f32, merge, computed, mask, mode);
        },
        .fma_pd => {
            const computed = try executeAccumulate(bits, meta, accum, lhs, rhs, features);
            return wide.applyLaneMask(bits, f64, merge, computed, mask, mode);
        },
        .fms_ps => {
            const computed = try executeAccumulate(bits, meta, accum, lhs, rhs, features);
            return wide.applyLaneMask(bits, f32, merge, computed, mask, mode);
        },
        .fms_pd => {
            const computed = try executeAccumulate(bits, meta, accum, lhs, rhs, features);
            return wide.applyLaneMask(bits, f64, merge, computed, mask, mode);
        },
        .fnma_ps => {
            const computed = try executeAccumulate(bits, meta, accum, lhs, rhs, features);
            return wide.applyLaneMask(bits, f32, merge, computed, mask, mode);
        },
        .fnma_pd => {
            const computed = try executeAccumulate(bits, meta, accum, lhs, rhs, features);
            return wide.applyLaneMask(bits, f64, merge, computed, mask, mode);
        },
        .fnms_ps => {
            const computed = try executeAccumulate(bits, meta, accum, lhs, rhs, features);
            return wide.applyLaneMask(bits, f32, merge, computed, mask, mode);
        },
        .fnms_pd => {
            const computed = try executeAccumulate(bits, meta, accum, lhs, rhs, features);
            return wide.applyLaneMask(bits, f64, merge, computed, mask, mode);
        },
        .fma_addsub_ps => {
            const computed = try executeAccumulate(bits, meta, accum, lhs, rhs, features);
            return wide.applyLaneMask(bits, f32, merge, computed, mask, mode);
        },
        .fma_addsub_pd => {
            const computed = try executeAccumulate(bits, meta, accum, lhs, rhs, features);
            return wide.applyLaneMask(bits, f64, merge, computed, mask, mode);
        },
        .fma_subadd_ps => {
            const computed = try executeAccumulate(bits, meta, accum, lhs, rhs, features);
            return wide.applyLaneMask(bits, f32, merge, computed, mask, mode);
        },
        .fma_subadd_pd => {
            const computed = try executeAccumulate(bits, meta, accum, lhs, rhs, features);
            return wide.applyLaneMask(bits, f64, merge, computed, mask, mode);
        },
        else => types.SafetyError.UnsupportedInstructionWidth,
    };
}

pub fn executeMove(comptime bits: usize, meta: types.InstructionMeta, value: wide.Wide(bits), features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    try types.validateMeta(meta);
    try types.requireFeature(meta, features);
    try types.requireWidth(meta, bits);
    return switch (meta.operation) {
        .move, .aligned_move, .unaligned_move, .non_temporal_move, .system_512, .key_256 => value,
        .duplicate_odd_ps => wide.duplicateOddF32(bits, value),
        .duplicate_even_ps => wide.duplicateEvenF32(bits, value),
        .duplicate_low_pd => wide.duplicateLowF64Per128(bits, value),
        .broadcast_lane => executeBroadcastLane(bits, meta, value),
        .move_high_low => wide.moveHighToLow(bits, value, value),
        .move_low_high => wide.moveLowToHigh(bits, value, value),
        .extract_element => value, // extract lane 0; ISA bridge applies the lane selector
        else => types.SafetyError.UnsupportedInstructionWidth,
    };
}

pub fn executeMovMask(comptime bits: usize, meta: types.InstructionMeta, value: wide.Wide(bits), features: types.FeatureSet) types.SafetyError!u32 {
    try types.validateMeta(meta);
    try types.requireFeature(meta, features);
    try types.requireWidth(meta, bits);
    return switch (meta.operation) {
        .movemask_ps => wide.movMaskPS(bits, value),
        .movemask_pd => wide.movMaskPD(bits, value),
        else => types.SafetyError.UnsupportedInstructionWidth,
    };
}

pub fn loadForInstruction(comptime bits: usize, meta: types.InstructionMeta, src: []const u8, features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    try types.validateMeta(meta);
    try types.requireFeature(meta, features);
    try types.requireWidth(meta, bits);
    return wide.loadBytesAligned(bits, src, meta.alignment);
}

/// Gather elements from memory at indexed addresses (VGATHER* / VPGATHER*).
/// Reads one element per lane at address `base + index[i] * scale`, where
/// `index` provides the lane-specific indices.  The gather result is merged
/// with `default_val` using `mask`.
///
/// Note: The caller (decoder / bridge) must have already verified that the
/// memory accesses are valid.  This function performs the element merging
/// but does not access guest memory (that's handled by the bridge layer).
pub fn gatherElements(
    comptime bits: usize,
    comptime T: type,
    default_val: wide.Wide(bits),
    index_vec: wide.Wide(bits),
    mask: u64,
    base: u64,
    scale: u8,
    loadElementFn: *const fn (addr: u64) T,
) wide.Wide(bits) {
    const lanes = comptime wide.laneCount(bits, T);
    const indices = wide.toArray(bits, T, index_vec);
    var result = wide.toArray(bits, T, default_val);
    const scale_factor: u64 = @as(u64, @intCast(scale));
    for (0..lanes) |lane| {
        const bit = (@as(u64, 1) << @intCast(lane));
        if ((mask & bit) != 0) {
            const index_val = @as(u64, @intCast(indices[lane]));
            const addr = base +% (index_val * scale_factor);
            result[lane] = loadElementFn(addr);
        }
    }
    return wide.fromArray(bits, T, result);
}

/// Scatter elements to memory at indexed addresses (VSCATTER* / VPSCATTER*).
/// Writes one element per lane to address `base + index[i] * scale`.
pub fn scatterElements(
    comptime bits: usize,
    comptime T: type,
    value: wide.Wide(bits),
    index_vec: wide.Wide(bits),
    mask: u64,
    base: u64,
    scale: u8,
    storeElementFn: *const fn (addr: u64, val: T) void,
) void {
    const lanes = comptime wide.laneCount(bits, T);
    const values = wide.toArray(bits, T, value);
    const indices = wide.toArray(bits, T, index_vec);
    const scale_factor: u64 = @as(u64, @intCast(scale));
    for (0..lanes) |lane| {
        const bit = (@as(u64, 1) << @intCast(lane));
        if ((mask & bit) != 0) {
            const index_val = @as(u64, @intCast(indices[lane]));
            const addr = base +% (index_val * scale_factor);
            storeElementFn(addr, values[lane]);
        }
    }
}

pub fn loadBroadcastForInstruction(comptime bits: usize, meta: types.InstructionMeta, src: []const u8, features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    if (!meta.supports_broadcast) return types.SafetyError.UnsupportedInstructionWidth;
    try types.validateMeta(meta);
    try types.requireFeature(meta, features);
    try types.requireWidth(meta, bits);
    const elem_bytes: usize = meta.element_bits / 8;
    if (src.len < elem_bytes) return types.SafetyError.BufferTooSmall;
    var result = wide.Wide(bits).zero();
    const lanes = bits / meta.element_bits;
    for (0..lanes) |lane| {
        @memcpy(result.bytes[(lane * elem_bytes)..][0..elem_bytes], src[0..elem_bytes]);
    }
    return result;
}

pub fn storeForInstruction(comptime bits: usize, meta: types.InstructionMeta, dst: []u8, value: wide.Wide(bits), features: types.FeatureSet) types.SafetyError!void {
    try types.validateMeta(meta);
    try types.requireFeature(meta, features);
    try types.requireWidth(meta, bits);
    try wide.storeBytesAligned(bits, dst, value, meta.alignment);
}

// ──── Shift operations (element-level shift by scalar or vector count) ────

fn executeShiftByVector(comptime bits: usize, meta: types.InstructionMeta, src: wide.Wide(bits), counts: wide.Wide(bits), comptime shift_op: wide.ShiftOp) types.SafetyError!wide.Wide(bits) {
    return switch (shift_op) {
        .shift_left => switch (meta.element_bits) {
            8 => wide.shiftLeftVariable(bits, i8, src, counts),
            16 => wide.shiftLeftVariable(bits, i16, src, counts),
            32 => wide.shiftLeftVariable(bits, i32, src, counts),
            64 => wide.shiftLeftVariable(bits, i64, src, counts),
            else => types.SafetyError.InvalidElementWidth,
        },
        .shift_right_arith => switch (meta.element_bits) {
            8 => wide.shiftRightArithVariable(bits, i8, src, counts),
            16 => wide.shiftRightArithVariable(bits, i16, src, counts),
            32 => wide.shiftRightArithVariable(bits, i32, src, counts),
            64 => wide.shiftRightArithVariable(bits, i64, src, counts),
            else => types.SafetyError.InvalidElementWidth,
        },
        .shift_right_logical => switch (meta.element_bits) {
            8 => wide.shiftRightLogVariable(bits, i8, src, counts),
            16 => wide.shiftRightLogVariable(bits, i16, src, counts),
            32 => wide.shiftRightLogVariable(bits, i32, src, counts),
            64 => wide.shiftRightLogVariable(bits, i64, src, counts),
            else => types.SafetyError.InvalidElementWidth,
        },
    };
}

// ──── Pack operations (saturating element narrowing) ─────────────────────

fn executePack(comptime bits: usize, meta: types.InstructionMeta, lhs: wide.Wide(bits), rhs: wide.Wide(bits), comptime pack_op: wide.PackOp) types.SafetyError!wide.Wide(bits) {
    return switch (pack_op) {
        .signed_saturate => switch (meta.element_bits) {
            16 => wide.packSigned(bits, i16, lhs, rhs),
            32 => wide.packSigned(bits, i32, lhs, rhs),
            else => types.SafetyError.InvalidElementWidth,
        },
        .unsigned_saturate => switch (meta.element_bits) {
            16 => wide.packUnsigned(bits, u16, lhs, rhs),
            32 => wide.packUnsigned(bits, u32, lhs, rhs),
            else => types.SafetyError.InvalidElementWidth,
        },
    };
}

// ──── P1 helper dispatch functions ───────────────────────────────────────

fn executeAbsValue(comptime bits: usize, meta: types.InstructionMeta, src: wide.Wide(bits)) types.SafetyError!wide.Wide(bits) {
    return switch (meta.element_bits) {
        8 => wide.absValue(bits, i8, src),
        16 => wide.absValue(bits, i16, src),
        32 => wide.absValue(bits, i32, src),
        64 => wide.absValue(bits, i64, src),
        else => types.SafetyError.InvalidElementWidth,
    };
}

fn executeBitwiseNot(comptime bits: usize, meta: types.InstructionMeta, src: wide.Wide(bits)) types.SafetyError!wide.Wide(bits) {
    return switch (meta.element_bits) {
        8 => wide.bitwiseNot(bits, u8, src),
        16 => wide.bitwiseNot(bits, u16, src),
        32 => wide.bitwiseNot(bits, u32, src),
        64 => wide.bitwiseNot(bits, u64, src),
        else => types.SafetyError.InvalidElementWidth,
    };
}

fn executeSignOperation(comptime bits: usize, meta: types.InstructionMeta, lhs: wide.Wide(bits), rhs: wide.Wide(bits)) types.SafetyError!wide.Wide(bits) {
    return switch (meta.element_bits) {
        8 => wide.signOperation(bits, i8, lhs, rhs),
        16 => wide.signOperation(bits, i16, lhs, rhs),
        32 => wide.signOperation(bits, i32, lhs, rhs),
        64 => wide.signOperation(bits, i64, lhs, rhs),
        else => types.SafetyError.InvalidElementWidth,
    };
}

fn executeUnpackLow(comptime bits: usize, meta: types.InstructionMeta, lhs: wide.Wide(bits), rhs: wide.Wide(bits)) types.SafetyError!wide.Wide(bits) {
    return switch (meta.element_bits) {
        8 => wide.unpackLow(bits, i8, lhs, rhs),
        16 => wide.unpackLow(bits, i16, lhs, rhs),
        32 => wide.unpackLow(bits, i32, lhs, rhs),
        64 => wide.unpackLow(bits, i64, lhs, rhs),
        else => types.SafetyError.InvalidElementWidth,
    };
}

fn executeUnpackHigh(comptime bits: usize, meta: types.InstructionMeta, lhs: wide.Wide(bits), rhs: wide.Wide(bits)) types.SafetyError!wide.Wide(bits) {
    return switch (meta.element_bits) {
        8 => wide.unpackHigh(bits, i8, lhs, rhs),
        16 => wide.unpackHigh(bits, i16, lhs, rhs),
        32 => wide.unpackHigh(bits, i32, lhs, rhs),
        64 => wide.unpackHigh(bits, i64, lhs, rhs),
        else => types.SafetyError.InvalidElementWidth,
    };
}

fn executeAbsValueMasked(comptime bits: usize, meta: types.InstructionMeta, merge: wide.Wide(bits), src: wide.Wide(bits), mask: u64, mode: wide.MaskMode) types.SafetyError!wide.Wide(bits) {
    const computed = try executeAbsValue(bits, meta, src);
    return switch (meta.element_bits) {
        8 => wide.applyLaneMask(bits, i8, merge, computed, mask, mode),
        16 => wide.applyLaneMask(bits, i16, merge, computed, mask, mode),
        32 => wide.applyLaneMask(bits, i32, merge, computed, mask, mode),
        64 => wide.applyLaneMask(bits, i64, merge, computed, mask, mode),
        else => types.SafetyError.InvalidElementWidth,
    };
}

fn executeBitwiseNotMasked(comptime bits: usize, meta: types.InstructionMeta, merge: wide.Wide(bits), src: wide.Wide(bits), mask: u64, mode: wide.MaskMode) types.SafetyError!wide.Wide(bits) {
    const computed = try executeBitwiseNot(bits, meta, src);
    return switch (meta.element_bits) {
        8 => wide.applyLaneMask(bits, u8, merge, computed, mask, mode),
        16 => wide.applyLaneMask(bits, u16, merge, computed, mask, mode),
        32 => wide.applyLaneMask(bits, u32, merge, computed, mask, mode),
        64 => wide.applyLaneMask(bits, u64, merge, computed, mask, mode),
        else => types.SafetyError.InvalidElementWidth,
    };
}

fn executeSignOperationMasked(comptime bits: usize, meta: types.InstructionMeta, merge: wide.Wide(bits), lhs: wide.Wide(bits), rhs: wide.Wide(bits), mask: u64, mode: wide.MaskMode) types.SafetyError!wide.Wide(bits) {
    const computed = try executeSignOperation(bits, meta, lhs, rhs);
    return switch (meta.element_bits) {
        8 => wide.applyLaneMask(bits, i8, merge, computed, mask, mode),
        16 => wide.applyLaneMask(bits, i16, merge, computed, mask, mode),
        32 => wide.applyLaneMask(bits, i32, merge, computed, mask, mode),
        64 => wide.applyLaneMask(bits, i64, merge, computed, mask, mode),
        else => types.SafetyError.InvalidElementWidth,
    };
}

fn executeUnpackLowMasked(comptime bits: usize, meta: types.InstructionMeta, merge: wide.Wide(bits), lhs: wide.Wide(bits), rhs: wide.Wide(bits), mask: u64, mode: wide.MaskMode) types.SafetyError!wide.Wide(bits) {
    const computed = try executeUnpackLow(bits, meta, lhs, rhs);
    return switch (meta.element_bits) {
        8 => wide.applyLaneMask(bits, i8, merge, computed, mask, mode),
        16 => wide.applyLaneMask(bits, i16, merge, computed, mask, mode),
        32 => wide.applyLaneMask(bits, i32, merge, computed, mask, mode),
        64 => wide.applyLaneMask(bits, i64, merge, computed, mask, mode),
        else => types.SafetyError.InvalidElementWidth,
    };
}

fn executeUnpackHighMasked(comptime bits: usize, meta: types.InstructionMeta, merge: wide.Wide(bits), lhs: wide.Wide(bits), rhs: wide.Wide(bits), mask: u64, mode: wide.MaskMode) types.SafetyError!wide.Wide(bits) {
    const computed = try executeUnpackHigh(bits, meta, lhs, rhs);
    return switch (meta.element_bits) {
        8 => wide.applyLaneMask(bits, i8, merge, computed, mask, mode),
        16 => wide.applyLaneMask(bits, i16, merge, computed, mask, mode),
        32 => wide.applyLaneMask(bits, i32, merge, computed, mask, mode),
        64 => wide.applyLaneMask(bits, i64, merge, computed, mask, mode),
        else => types.SafetyError.InvalidElementWidth,
    };
}

fn executeBroadcastLane(comptime bits: usize, meta: types.InstructionMeta, src: wide.Wide(bits)) types.SafetyError!wide.Wide(bits) {
    return switch (meta.element_bits) {
        8 => wide.broadcastLane(bits, i8, src),
        16 => wide.broadcastLane(bits, i16, src),
        32 => wide.broadcastLane(bits, i32, src),
        64 => wide.broadcastLane(bits, i64, src),
        128 => blk: {
            // VBROADCASTF128/I128: replicate first 128-bit block to all 128-bit lanes
            const block_bytes: usize = 16;
            var result = src;
            const lanes = bits / 128;
            for (1..lanes) |lane| {
                @memcpy(result.bytes[(lane * block_bytes)..][0..block_bytes], result.bytes[0..block_bytes]);
            }
            break :blk result;
        },
        256 => blk: {
            // VBROADCASTF32X8/I32X8/F64X4/I64X4: replicate first 256-bit block across all 256-bit lanes
            const block_bytes: usize = 32;
            var result = src;
            const lanes = bits / 256;
            for (1..lanes) |lane| {
                @memcpy(result.bytes[(lane * block_bytes)..][0..block_bytes], result.bytes[0..block_bytes]);
            }
            break :blk result;
        },
        else => types.SafetyError.InvalidElementWidth,
    };
}

/// INSERTPS: insert scalar f32 from rhs[imm[7:6]] into result[imm[5:4]]
/// with zero-masking of destination dwords via imm[3:0].
fn executeInsertPS(comptime bits: usize, meta: types.InstructionMeta, lhs: wide.Wide(bits), rhs: wide.Wide(bits), immediate: u8) types.SafetyError!wide.Wide(bits) {
    _ = meta;
    return wide.insertPS(bits, lhs, rhs, immediate);
}

// ──── P3 helper dispatch functions ───────────────────────────────────────

fn executeAverage(comptime bits: usize, meta: types.InstructionMeta, lhs: wide.Wide(bits), rhs: wide.Wide(bits)) types.SafetyError!wide.Wide(bits) {
    return switch (meta.element_bits) {
        8 => wide.average(bits, u8, lhs, rhs),
        16 => wide.average(bits, u16, lhs, rhs),
        else => types.SafetyError.InvalidElementWidth,
    };
}

fn executeAlign(comptime bits: usize, meta: types.InstructionMeta, lhs: wide.Wide(bits), rhs: wide.Wide(bits), imm: u8) types.SafetyError!wide.Wide(bits) {
    return switch (meta.element_bits) {
        32 => wide.@"align"(bits, u32, lhs, rhs, imm),
        64 => wide.@"align"(bits, u64, lhs, rhs, imm),
        else => types.SafetyError.InvalidElementWidth,
    };
}

const RotateDirection = enum { left, right };

fn executeRotateImmediate(comptime bits: usize, meta: types.InstructionMeta, lhs: wide.Wide(bits), rhs: wide.Wide(bits), imm: u8, comptime dir: RotateDirection) types.SafetyError!wide.Wide(bits) {
    _ = lhs; // destination register (merge-masked if masking is active)
    const count = imm & 0x3F; // 6-bit rotate count (valid for up to 64-bit elements)
    return switch (dir) {
        .left => switch (meta.element_bits) {
            32 => wide.rotateLeft(bits, i32, rhs, count),
            64 => wide.rotateLeft(bits, i64, rhs, count),
            else => types.SafetyError.InvalidElementWidth,
        },
        .right => switch (meta.element_bits) {
            32 => wide.rotateRight(bits, i32, rhs, count),
            64 => wide.rotateRight(bits, i64, rhs, count),
            else => types.SafetyError.InvalidElementWidth,
        },
    };
}

fn executeRotateVariable(comptime bits: usize, meta: types.InstructionMeta, src: wide.Wide(bits), counts: wide.Wide(bits), comptime dir: RotateDirection) types.SafetyError!wide.Wide(bits) {
    return switch (dir) {
        .left => switch (meta.element_bits) {
            32 => wide.rotateLeftVariable(bits, i32, src, counts),
            64 => wide.rotateLeftVariable(bits, i64, src, counts),
            else => types.SafetyError.InvalidElementWidth,
        },
        .right => switch (meta.element_bits) {
            32 => wide.rotateRightVariable(bits, i32, src, counts),
            64 => wide.rotateRightVariable(bits, i64, src, counts),
            else => types.SafetyError.InvalidElementWidth,
        },
    };
}

// ──── P3 helper dispatch functions (BITWISE, GALOIS, ROUND, SHA, PERMUTE) ─

fn executeTernaryLogic(comptime bits: usize, meta: types.InstructionMeta, lhs: wide.Wide(bits), rhs: wide.Wide(bits), imm: u8) types.SafetyError!wide.Wide(bits) {
    return switch (meta.element_bits) {
        32 => wide.ternaryLogic(bits, u32, lhs, rhs, imm),
        64 => wide.ternaryLogic(bits, u64, lhs, rhs, imm),
        else => types.SafetyError.InvalidElementWidth,
    };
}

fn executeGf2p8Mul(comptime bits: usize, meta: types.InstructionMeta, lhs: wide.Wide(bits), rhs: wide.Wide(bits)) types.SafetyError!wide.Wide(bits) {
    _ = meta;
    return wide.gf2p8Mul(bits, lhs, rhs);
}

fn executeGf2p8Affine(comptime bits: usize, meta: types.InstructionMeta, lhs: wide.Wide(bits), rhs: wide.Wide(bits), imm: u8) types.SafetyError!wide.Wide(bits) {
    _ = meta;
    return wide.gf2p8Affine(bits, lhs, rhs, imm);
}

fn executeGf2p8AffineInv(comptime bits: usize, meta: types.InstructionMeta, lhs: wide.Wide(bits), rhs: wide.Wide(bits), imm: u8) types.SafetyError!wide.Wide(bits) {
    _ = meta;
    return wide.gf2p8AffineInv(bits, lhs, rhs, imm);
}

fn executeRoundToInt(comptime bits: usize, meta: types.InstructionMeta, src: wide.Wide(bits)) types.SafetyError!wide.Wide(bits) {
    return switch (meta.element_bits) {
        32 => wide.roundToInt(bits, f32, src),
        64 => wide.roundToInt(bits, f64, src),
        else => types.SafetyError.InvalidElementWidth,
    };
}

const ShaOp = enum { msg1, msg2, nexte, sha256_msg1, sha256_msg2, sha256_rnds2 };

fn executeShaOp(comptime bits: usize, meta: types.InstructionMeta, lhs: wide.Wide(bits), rhs: wide.Wide(bits), comptime op: ShaOp) types.SafetyError!wide.Wide(bits) {
    _ = meta;
    return switch (op) {
        .msg1 => wide.sha1Msg1(bits, lhs, rhs),
        .msg2 => wide.sha1Msg2(bits, lhs, rhs),
        .nexte => wide.sha1Nexte(bits, lhs, rhs),
        .sha256_msg1 => wide.sha256Msg1(bits, lhs, rhs),
        .sha256_msg2 => wide.sha256Msg2(bits, lhs, rhs),
        .sha256_rnds2 => wide.sha256Rnds2(bits, lhs, rhs),
    };
}

fn executeShaRnds4(comptime bits: usize, meta: types.InstructionMeta, lhs: wide.Wide(bits), rhs: wide.Wide(bits), imm: u8) types.SafetyError!wide.Wide(bits) {
    _ = meta;
    return wide.sha1Rnds4(bits, lhs, rhs, imm);
}

/// Three-source dispatch for two_source_permute (VPERMI2/VPERMT2).
pub fn executeThreeSource(comptime bits: usize, meta: types.InstructionMeta, src1: wide.Wide(bits), src2: wide.Wide(bits), src3: wide.Wide(bits), features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    try types.validateMeta(meta);
    try types.requireFeature(meta, features);
    try types.requireWidth(meta, bits);
    return switch (meta.operation) {
        .two_source_permute => executeTwoSourcePermute(bits, meta, src1, src2, src3),
        else => types.SafetyError.UnsupportedInstructionWidth,
    };
}

fn executeTwoSourcePermute(comptime bits: usize, meta: types.InstructionMeta, index: wide.Wide(bits), src2: wide.Wide(bits), src3: wide.Wide(bits)) types.SafetyError!wide.Wide(bits) {
    return switch (meta.element_bits) {
        8 => wide.twoSourcePermute(bits, u8, index, src2, src3),
        16 => wide.twoSourcePermute(bits, u16, index, src2, src3),
        32 => wide.twoSourcePermute(bits, u32, index, src2, src3),
        64 => wide.twoSourcePermute(bits, u64, index, src2, src3),
        else => types.SafetyError.InvalidElementWidth,
    };
}

fn executePermil(comptime bits: usize, meta: types.InstructionMeta, lhs: wide.Wide(bits), rhs: wide.Wide(bits), imm: u8) types.SafetyError!wide.Wide(bits) {
    _ = lhs;
    return switch (meta.element_bits) {
        32 => wide.permil(bits, f32, rhs, imm),
        64 => wide.permil(bits, f64, rhs, imm),
        else => types.SafetyError.InvalidElementWidth,
    };
}

// ──── P4 helper dispatch functions (SCALE, RANGE, FIXUP, COMPRESS, EXPAND) ─

fn executeScaleFloat(comptime bits: usize, meta: types.InstructionMeta, lhs: wide.Wide(bits), rhs: wide.Wide(bits), comptime T: type) types.SafetyError!wide.Wide(bits) {
    _ = meta;
    return wide.scaleFloat(bits, T, lhs, rhs);
}

fn executeRangeFloat(comptime bits: usize, meta: types.InstructionMeta, lhs: wide.Wide(bits), rhs: wide.Wide(bits), imm: u8, comptime T: type) types.SafetyError!wide.Wide(bits) {
    _ = meta;
    return wide.rangeFloat(bits, T, lhs, rhs, imm);
}

fn executeFixupFloat(comptime bits: usize, meta: types.InstructionMeta, lhs: wide.Wide(bits), rhs: wide.Wide(bits), imm: u8, comptime T: type) types.SafetyError!wide.Wide(bits) {
    _ = meta;
    return wide.fixupFloat(bits, T, lhs, rhs, imm);
}

fn executeCompressFloat(comptime bits: usize, meta: types.InstructionMeta, src: wide.Wide(bits), comptime T: type) types.SafetyError!wide.Wide(bits) {
    _ = meta;
    return wide.compressFloat(bits, T, src);
}

fn executeExpandFloat(comptime bits: usize, meta: types.InstructionMeta, src: wide.Wide(bits), comptime T: type) types.SafetyError!wide.Wide(bits) {
    _ = meta;
    return wide.expandFloat(bits, T, src);
}

/// Insert a scalar element from rhs into lhs at the lane position selected
/// by `lane`.  The scalar is read from the first element of `rhs`.
fn executeInsertElement(comptime bits: usize, meta: types.InstructionMeta, lhs: wide.Wide(bits), rhs: wide.Wide(
    bits,
), lane: usize) types.SafetyError!wide.Wide(bits) {
    return switch (meta.element_bits) {
        8 => blk: {
            const arr = wide.toArray(bits, i8, rhs);
            var result = wide.toArray(bits, i8, lhs);
            if (lane < result.len) result[lane] = arr[0];
            break :blk wide.fromArray(bits, i8, result);
        },
        16 => blk: {
            const arr = wide.toArray(bits, i16, rhs);
            var result = wide.toArray(bits, i16, lhs);
            if (lane < result.len) result[lane] = arr[0];
            break :blk wide.fromArray(bits, i16, result);
        },
        32 => blk: {
            const arr = wide.toArray(bits, i32, rhs);
            var result = wide.toArray(bits, i32, lhs);
            if (lane < result.len) result[lane] = arr[0];
            break :blk wide.fromArray(bits, i32, result);
        },
        64 => blk: {
            const arr = wide.toArray(bits, i64, rhs);
            var result = wide.toArray(bits, i64, lhs);
            if (lane < result.len) result[lane] = arr[0];
            break :blk wide.fromArray(bits, i64, result);
        },
        else => types.SafetyError.InvalidElementWidth,
    };
}
