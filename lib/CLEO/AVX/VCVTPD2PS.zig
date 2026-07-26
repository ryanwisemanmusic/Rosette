const types = @import("../types.zig");
const instruction = @import("../instruction.zig");
const wide = @import("../wide.zig");

pub const meta = types.InstructionMeta{
    .name = "VCVTPD2PS",
    .family = "CONVERT",
    .source_path = "ISA/x86/CONVERT/VCVTPD2PS.inc",
    .required_feature = .avx,
    .max_width_bits = 256,
    .element_bits = 64,
    .operation = .cvt_pd2ps,
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
