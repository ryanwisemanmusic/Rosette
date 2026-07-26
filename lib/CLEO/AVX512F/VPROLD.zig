const types = @import("../types.zig");
const instruction = @import("../instruction.zig");
const wide = @import("../wide.zig");

pub const meta = types.InstructionMeta{
    .name = "VPROLD",
    .family = "ROTATE",
    .source_path = "ISA/x86/ROTATE/VPROLD.inc",
    .required_feature = .avx512f,
    .max_width_bits = 512,
    .element_bits = 32,
    .operation = .rotate_left,
    .alignment = .any,
    .supports_masking = true,
    .supports_broadcast = true,
};

pub fn plan() types.LoweringPlan { return meta.plan(); }
pub fn safety(features: types.FeatureSet) types.SafetyReport { return instruction.safety(meta, features); }
pub fn validate() types.SafetyError!void { try instruction.validate(meta); }
pub fn binary(comptime bits: usize, lhs: wide.Wide(bits), rhs: wide.Wide(bits), features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    return instruction.binaryImmediate(bits, meta, lhs, rhs, 0, features);
}
pub fn executeImmediate(comptime bits: usize, lhs: wide.Wide(bits), rhs: wide.Wide(bits), immediate: u8, features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    return instruction.binaryImmediate(bits, meta, lhs, rhs, immediate, features);
}
pub fn move(comptime bits: usize, value: wide.Wide(bits), features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    return instruction.move(bits, meta, value, features);
}
