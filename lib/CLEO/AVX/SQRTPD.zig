const types = @import("../types.zig");
const instruction = @import("../instruction.zig");
const wide = @import("../wide.zig");

pub const meta = types.InstructionMeta{
    .name = "SQRTPD",
    .family = "SQUARE_ROOT",
    .source_path = "ISA/x86/SQUARE_ROOT/SQRTPD.inc",
    .required_feature = .avx,
    .max_width_bits = 256,
    .element_bits = 64,
    .operation = .sqrt_pd,
    .alignment = .any,
    .supports_masking = false,
    .supports_broadcast = false,
};

pub fn plan() types.LoweringPlan {
    return meta.plan();
}

pub fn safety(features: types.FeatureSet) types.SafetyReport {
    return instruction.safety(meta, features);
}

pub fn validate() types.SafetyError!void {
    try instruction.validate(meta);
}

pub fn execute(comptime bits: usize, lhs: wide.Wide(bits), rhs: wide.Wide(bits), features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    _ = rhs;
    return instruction.unary(bits, meta, lhs, features);
}

pub fn executeMasked(comptime bits: usize, merge: wide.Wide(bits), lhs: wide.Wide(bits), rhs: wide.Wide(bits), mask: u64, mode: wide.MaskMode, features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    _ = rhs;
    return instruction.unaryMasked(bits, meta, merge, lhs, mask, mode, features);
}

pub fn move(comptime bits: usize, value: wide.Wide(bits), features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    return instruction.move(bits, meta, value, features);
}

pub fn movMask(comptime bits: usize, value: wide.Wide(bits), features: types.FeatureSet) types.SafetyError!u32 {
    return instruction.movMask(bits, meta, value, features);
}
