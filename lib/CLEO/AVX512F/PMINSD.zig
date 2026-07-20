const Impl = @import("../wrapper.zig").BinaryInstruction(.{
    .name = "PMINSD",
    .family = "MIN-MAX",
    .source_path = "ISA/x86/MIN-MAX/PMINSD.inc",
    .required_feature = .avx512f,
    .max_width_bits = 512,
    .element_bits = 32,
    .operation = .pmin_signed,
    .supports_masking = true,
    .supports_broadcast = true,
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
pub const loadBroadcast = Impl.loadBroadcast;
pub const movMask = Impl.movMask;
