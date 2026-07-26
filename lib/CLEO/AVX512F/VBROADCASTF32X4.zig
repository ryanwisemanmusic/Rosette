const types = @import("../types.zig");
const instruction = @import("../instruction.zig");
const wide = @import("../wide.zig");

pub const meta = types.InstructionMeta{
    .name = "VBROADCASTF32X4",
    .family = "LOAD",
    .source_path = "ISA/x86/LOAD/VBROADCASTF32X4.inc",
    .required_feature = .avx512f,
    .max_width_bits = 512,
    .element_bits = 128,
    .operation = .broadcast_lane,
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
pub fn execute(comptime bits: usize, src: wide.Wide(bits), features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    return instruction.move(bits, meta, src, features);
}
pub fn move(comptime bits: usize, value: wide.Wide(bits), features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    return instruction.move(bits, meta, value, features);
}
