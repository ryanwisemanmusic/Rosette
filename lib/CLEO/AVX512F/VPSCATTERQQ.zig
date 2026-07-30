const types = @import("../types.zig");
const instruction = @import("../instruction.zig");
const wide = @import("../wide.zig");

pub const meta = types.InstructionMeta{
    .name = "VPSCATTERQQ",
    .family = "SCATTER",
    .source_path = "ISA/x86/SCATTER/VPSCATTERQQ.inc",
    .required_feature = .avx512f,
    .max_width_bits = 512,
    .element_bits = 64,
    .operation = .scatter_q,
    .alignment = .any,
    .supports_masking = true,
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
    return instruction.binary(bits, meta, lhs, rhs, features);
}
pub fn move(comptime bits: usize, value: wide.Wide(bits), features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    return instruction.move(bits, meta, value, features);
}
