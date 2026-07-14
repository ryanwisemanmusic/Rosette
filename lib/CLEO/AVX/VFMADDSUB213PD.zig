const Impl = @import("../wrapper.zig").BinaryInstruction(.{
    .name = "VFMADDSUB213PD",
    .family = "FUSED",
    .source_path = "ISA/x86/FUSED/VFMADDSUB213PD.inc",
    .required_feature = .fma,
    .max_width_bits = 256,
    .element_bits = 64,
    .operation = .fma_addsub_pd,
    .supports_masking = false,
    .supports_broadcast = false,
});

pub const meta = Impl.meta;
pub const plan = Impl.plan;
pub const safety = Impl.safety;
pub const validate = Impl.validate;
pub const execute = Impl.execute;
pub const executeAccumulate = Impl.executeAccumulate;
pub const executeMasked = Impl.executeMasked;
pub const executeMaskedImmediate = Impl.executeMaskedImmediate;
pub const executeAccumulateMasked = Impl.executeAccumulateMasked;
pub const move = Impl.move;
pub const movMask = Impl.movMask;
