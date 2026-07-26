const types = @import("../types.zig");
const instruction = @import("../instruction.zig");
const wide = @import("../wide.zig");

pub const meta = types.InstructionMeta{
    .name = "VPABSD",
    .family = "ABSOLUTE",
    .source_path = "ISA/x86/ABSOLUTE/VPABSD.inc",
    .required_feature = .avx2,
    .max_width_bits = 256,
    .element_bits = 32,
    .operation = .pabs,
    .alignment = .any,
    .supports_masking = false,
    .supports_broadcast = false,
};

pub fn plan() types.LoweringPlan { return meta.plan(); }
pub fn safety(features: types.FeatureSet) types.SafetyReport { return instruction.safety(meta, features); }
pub fn validate() types.SafetyError!void { try instruction.validate(meta); }
pub fn unary(comptime bits: usize, src: wide.Wide(bits), features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    return instruction.unary(bits, meta, src, features);
}
pub fn move(comptime bits: usize, value: wide.Wide(bits), features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    return instruction.move(bits, meta, value, features);
}
