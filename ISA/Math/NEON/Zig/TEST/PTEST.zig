const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "PTEST",
    .family = "TEST",
    .path = "TEST/PTEST.inc",
    .source_table_path = "TEST/PTEST.inc",
    .target_isa = .neon,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "PTEST", .path = "TEST/PTEST.inc", .encoding_count = 3, .source_path_len = 14 } },
    .{ .documented_contract = .{ .name = "PTEST", .path = "TEST/PTEST.inc", .encoding_count = 3, .source_path_len = 14 } },
};

pub const proof_report = proofs.ProofReport{
    .meta = meta,
    .cases = proof_cases[0..],
};

pub fn proofReport() proofs.ProofReport {
    return proof_report;
}

pub fn verifyProofs() !void {
    try proofs.verifyReport(proofReport());
}

test "neon PTEST documented-contract proofs match table metadata" {
    try verifyProofs();
}
