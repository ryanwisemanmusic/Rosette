const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "DPPS",
    .family = "DOT_PRODUCT",
    .path = "DOT_PRODUCT/DPPS.inc",
    .source_table_path = "DOT_PRODUCT/DPPS.inc",
    .target_isa = .neon,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "DPPS", .path = "DOT_PRODUCT/DPPS.inc", .encoding_count = 3, .source_path_len = 20 } },
    .{ .documented_contract = .{ .name = "DPPS", .path = "DOT_PRODUCT/DPPS.inc", .encoding_count = 3, .source_path_len = 20 } },
};

pub const proof_report = proofs.ProofReport{
    .meta = meta,
    .cases = proof_cases[0..],
};
