const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "TDPBSSD",
    .family = "DOT_PRODUCT",
    .path = "DOT_PRODUCT/TDPBSSD.inc",
    .source_table_path = "DOT_PRODUCT/TDPBSSD.inc",
    .target_isa = .x86,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "TDPBSSD", .path = "DOT_PRODUCT/TDPBSSD.inc", .encoding_count = 1, .source_path_len = 23 } },
    .{ .documented_contract = .{ .name = "TDPBSSD", .path = "DOT_PRODUCT/TDPBSSD.inc", .encoding_count = 1, .source_path_len = 23 } },
};

pub const proof_report = proofs.ProofReport{
    .meta = meta,
    .cases = proof_cases[0..],
};
