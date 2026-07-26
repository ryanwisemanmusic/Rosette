const types = @import("types.zig");
const ops = @import("ops.zig");
const wide = @import("wide.zig");

pub fn safety(meta: types.InstructionMeta, features: types.FeatureSet) types.SafetyReport {
    return types.safetyReport(meta, features);
}

pub fn validate(meta: types.InstructionMeta) types.SafetyError!void {
    try types.validateMeta(meta);
}

pub fn binary(comptime bits: usize, meta: types.InstructionMeta, lhs: wide.Wide(bits), rhs: wide.Wide(bits), features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    return ops.executeBinary(bits, meta, lhs, rhs, features);
}

pub fn unary(comptime bits: usize, meta: types.InstructionMeta, src: wide.Wide(bits), features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    return ops.executeUnary(bits, meta, src, features);
}

pub fn unaryMasked(comptime bits: usize, meta: types.InstructionMeta, merge: wide.Wide(bits), src: wide.Wide(bits), mask: u64, mode: wide.MaskMode, features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    return ops.executeUnaryMasked(bits, meta, merge, src, mask, mode, features);
}

pub fn binaryImmediate(comptime bits: usize, meta: types.InstructionMeta, lhs: wide.Wide(bits), rhs: wide.Wide(bits), immediate: u8, features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    return ops.executeBinaryImmediate(bits, meta, lhs, rhs, immediate, features);
}

pub fn blendVariable(comptime bits: usize, meta: types.InstructionMeta, lhs: wide.Wide(bits), rhs: wide.Wide(bits), selector: wide.Wide(bits), features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    return ops.executeBlendVariable(bits, meta, lhs, rhs, selector, features);
}

pub fn accumulate(comptime bits: usize, meta: types.InstructionMeta, accum: wide.Wide(bits), lhs: wide.Wide(bits), rhs: wide.Wide(bits), features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    return ops.executeAccumulate(bits, meta, accum, lhs, rhs, features);
}

pub fn binaryMasked(comptime bits: usize, meta: types.InstructionMeta, merge: wide.Wide(bits), lhs: wide.Wide(bits), rhs: wide.Wide(bits), mask: u64, mode: wide.MaskMode, features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    return ops.executeBinaryMasked(bits, meta, merge, lhs, rhs, mask, mode, features);
}

pub fn binaryMaskedImmediate(comptime bits: usize, meta: types.InstructionMeta, merge: wide.Wide(bits), lhs: wide.Wide(bits), rhs: wide.Wide(bits), immediate: u8, mask: u64, mode: wide.MaskMode, features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    return ops.executeBinaryMaskedImmediate(bits, meta, merge, lhs, rhs, immediate, mask, mode, features);
}

pub fn accumulateMasked(comptime bits: usize, meta: types.InstructionMeta, merge: wide.Wide(bits), accum: wide.Wide(bits), lhs: wide.Wide(bits), rhs: wide.Wide(bits), mask: u64, mode: wide.MaskMode, features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    return ops.executeAccumulateMasked(bits, meta, merge, accum, lhs, rhs, mask, mode, features);
}

pub fn broadcastLoad(comptime bits: usize, meta: types.InstructionMeta, src: []const u8, features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    return ops.loadBroadcastForInstruction(bits, meta, src, features);
}

pub fn move(comptime bits: usize, meta: types.InstructionMeta, value: wide.Wide(bits), features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    return ops.executeMove(bits, meta, value, features);
}

pub fn movMask(comptime bits: usize, meta: types.InstructionMeta, value: wide.Wide(bits), features: types.FeatureSet) types.SafetyError!u32 {
    return ops.executeMovMask(bits, meta, value, features);
}

pub fn downConvert(comptime bits: usize, meta: types.InstructionMeta, src: wide.Wide(bits), comptime InT: type, comptime OutT: type, comptime mode: wide.DownConvertMode, features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    try types.validateMeta(meta);
    try types.requireFeature(meta, features);
    try types.requireWidth(meta, bits);
    return wide.downConvert(bits, InT, OutT, src, mode);
}
