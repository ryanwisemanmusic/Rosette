const types = @import("../types.zig");
const instruction = @import("../instruction.zig");
const wide = @import("../wide.zig");

pub const meta = types.InstructionMeta{
    .name = "SHA256RNDS2",
    .family = "SHA",
    .source_path = "ISA/x86/SHA/SHA256RNDS2.inc",
    .required_feature = .sha,
    .max_width_bits = 256,
    .element_bits = 32,
    .operation = .sha256_rnds2,
    .alignment = .any,
    .supports_masking = false,
    .supports_broadcast = false,
};

pub fn plan() types.LoweringPlan { return meta.plan(); }
pub fn safety(features: types.FeatureSet) types.SafetyReport { return instruction.safety(meta, features); }
pub fn validate() types.SafetyError!void { try instruction.validate(meta); }
pub fn execute(comptime bits: usize, lhs: wide.Wide(bits), rhs: wide.Wide(bits), features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    return instruction.binary(bits, meta, lhs, rhs, features);
}
pub fn move(comptime bits: usize, value: wide.Wide(bits), features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    return instruction.move(bits, meta, value, features);
}
