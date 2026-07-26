const types = @import("../types.zig");
const instruction = @import("../instruction.zig");
const wide = @import("../wide.zig");

pub const meta = types.InstructionMeta{
    .name = "VPMOVUSWB",
    .family = "DOWN_CONVERT",
    .source_path = "ISA/x86/DOWN_CONVERT/VPMOVUSWB.inc",
    .required_feature = .avx512bw,
    .max_width_bits = 512,
    .element_bits = 16,
    .operation = .down_convert_unsigned,
    .alignment = .any,
    .supports_masking = false,
    .supports_broadcast = false,
};

pub fn plan() types.LoweringPlan { return meta.plan(); }
pub fn safety(features: types.FeatureSet) types.SafetyReport { return instruction.safety(meta, features); }
pub fn validate() types.SafetyError!void { try instruction.validate(meta); }
pub fn unary(comptime bits: usize, src: wide.Wide(bits), features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    return instruction.downConvert(bits, meta, src, u16, u8, .unsigned_saturate, features);
}
pub fn move(comptime bits: usize, value: wide.Wide(bits), features: types.FeatureSet) types.SafetyError!wide.Wide(bits) {
    return instruction.move(bits, meta, value, features);
}
