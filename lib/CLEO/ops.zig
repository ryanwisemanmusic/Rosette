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
