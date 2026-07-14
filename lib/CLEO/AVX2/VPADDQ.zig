const Impl = @import("../wrapper.zig").BinaryInstruction(.{
    .name = "VPADDQ",
    .family = "ADD",
    .source_path = "ISA/x86/ADD/PADDQ.inc",
    .required_feature = .avx2,
    .max_width_bits = 256,
    .element_bits = 64,
    .operation = .padd,
});

pub const meta = Impl.meta;
pub const plan = Impl.plan;
pub const safety = Impl.safety;
pub const validate = Impl.validate;
pub const execute = Impl.execute;
pub const executeImmediate = Impl.executeImmediate;
pub const executeAccumulate = Impl.executeAccumulate;
pub const executeMasked = Impl.executeMasked;
pub const executeMaskedImmediate = Impl.executeMaskedImmediate;
pub const executeAccumulateMasked = Impl.executeAccumulateMasked;
pub const move = Impl.move;
pub const movMask = Impl.movMask;
