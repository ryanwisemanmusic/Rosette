const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "VDPBF16PS",
    .family = "DOT_PRODUCT",
    .path = "DOT_PRODUCT/VDPBF16PS.inc",
    .source_table_path = "DOT_PRODUCT/VDPBF16PS.inc",
    .target_isa = .x86,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "VDPBF16PS", .path = "DOT_PRODUCT/VDPBF16PS.inc", .encoding_count = 3, .source_path_len = 25 } },
    .{ .documented_contract = .{ .name = "VDPBF16PS", .path = "DOT_PRODUCT/VDPBF16PS.inc", .encoding_count = 3, .source_path_len = 25 } },
};

pub const proof_report = proofs.ProofReport{
    .meta = meta,
    .cases = proof_cases[0..],
};
