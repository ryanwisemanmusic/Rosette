const Impl = @import("../wrapper.zig").BinaryInstruction(.{
    .name = "VFNMADD132PS",
    .family = "FUSED",
    .source_path = "ISA/x86/FUSED/VFNMADD132PS.inc",
    .required_feature = .avx512f,
    .max_width_bits = 512,
    .element_bits = 32,
    .operation = .fnma_ps,
    .supports_masking = true,
    .supports_broadcast = true,
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
pub const loadBroadcast = Impl.loadBroadcast;
pub const movMask = Impl.movMask;
