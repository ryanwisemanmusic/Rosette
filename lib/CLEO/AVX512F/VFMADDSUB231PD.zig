const Impl = @import("../wrapper.zig").BinaryInstruction(.{
    .name = "VFMADDSUB231PD",
    .family = "FUSED",
    .source_path = "ISA/x86/FUSED/VFMADDSUB231PD.inc",
    .required_feature = .avx512f,
    .max_width_bits = 512,
    .element_bits = 64,
    .operation = .fma_addsub_pd,
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
