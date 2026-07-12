const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "VPERMILPD",
    .family = "PERMUTE",
    .path = "PERMUTE/VPERMILPD.inc",
    .source_table_path = "PERMUTE/VPERMILPD.inc",
    .target_isa = .neon,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "VPERMILPD", .path = "PERMUTE/VPERMILPD.inc", .encoding_count = 10, .source_path_len = 14 } },
    .{ .documented_contract = .{ .name = "VPERMILPD", .path = "PERMUTE/VPERMILPD.inc", .encoding_count = 10, .source_path_len = 14 } },
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

test "neon VPERMILPD documented-contract proofs match table metadata" {
    try verifyProofs();
}
