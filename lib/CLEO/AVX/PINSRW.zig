const types = @import("../types.zig");
const instruction = @import("../instruction.zig");
const wide = @import("../wide.zig");

pub const meta = types.InstructionMeta{
    .name = "PINSRW",
    .family = "INSERT",
    .source_path = "ISA/x86/INSERT/PINSRW.inc",
    .required_feature = .avx,
    .max_width_bits = 256,
    .element_bits = 16,
    .operation = .insert_element,
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
pub fn executeImmediate(comptime bits: usize, lhs: wide.Wide(bits), rhs: wide.Wide(bits), immediate: u8, features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    return instruction.binaryImmediate(bits, meta, lhs, rhs, immediate, features);
}
pub fn move(comptime bits: usize, value: wide.Wide(bits), features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    return instruction.move(bits, meta, value, features);
}
