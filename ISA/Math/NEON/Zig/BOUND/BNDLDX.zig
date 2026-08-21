const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "BNDLDX",
    .family = "BOUND",
    .path = "BOUND/BNDLDX.inc",
    .source_table_path = "BOUND/BNDLDX.inc",
    .target_isa = .neon,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "BNDLDX", .path = "BOUND/BNDLDX.inc", .encoding_count = 1, .source_path_len = 16 } },
    .{ .documented_contract = .{ .name = "BNDLDX", .path = "BOUND/BNDLDX.inc", .encoding_count = 1, .source_path_len = 16 } },
};

pub const proof_report = proofs.ProofReport{
    .meta = meta,
    .cases = proof_cases[0..],
};
