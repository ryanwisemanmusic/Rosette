const types = @import("../types.zig");
const instruction = @import("../instruction.zig");
const wide = @import("../wide.zig");

pub const meta = types.InstructionMeta{
    .name = "CVTPD2DQ",
    .family = "CONVERT",
    .source_path = "ISA/x86/CONVERT/CVTPD2DQ.inc",
    .required_feature = .avx512f,
    .max_width_bits = 512,
    .element_bits = 64,
    .operation = .cvt_pd2dq,
    .alignment = .any,
    .supports_masking = true,
    .supports_broadcast = false,
};

pub fn plan() types.LoweringPlan { return meta.plan(); }
pub fn safety(features: types.FeatureSet) types.SafetyReport { return instruction.safety(meta, features); }
pub fn validate() types.SafetyError!void { try instruction.validate(meta); }
pub fn execute(comptime bits: usize, src: wide.Wide(bits), features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    return instruction.unary(bits, meta, src, features);
}
pub fn move(comptime bits: usize, value: wide.Wide(bits), features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    return instruction.move(bits, meta, value, features);
}
