const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "BNDCL",
    .family = "BOUND",
    .path = "BOUND/BNDCL.inc",
    .source_table_path = "BOUND/BNDCL.inc",
    .target_isa = .neon,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "BNDCL", .path = "BOUND/BNDCL.inc", .encoding_count = 2, .source_path_len = 15 } },
    .{ .documented_contract = .{ .name = "BNDCL", .path = "BOUND/BNDCL.inc", .encoding_count = 2, .source_path_len = 15 } },
};

pub const proof_report = proofs.ProofReport{
    .meta = meta,
    .cases = proof_cases[0..],
};
