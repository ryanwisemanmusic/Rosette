const types = @import("../types.zig");
const instruction = @import("../instruction.zig");
const wide = @import("../wide.zig");

pub const meta = types.InstructionMeta{
    .name = "MOVLPS",
    .family = "MOV",
    .source_path = "ISA/x86/MOV/MOVLPS.inc",
    .required_feature = .sse,
    .max_width_bits = 128,
    .element_bits = 32,
    .operation = .move,
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
pub fn move(comptime bits: usize, value: wide.Wide(bits), features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    return instruction.move(bits, meta, value, features);
}
