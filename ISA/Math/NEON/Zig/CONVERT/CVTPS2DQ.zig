const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "CVTPS2DQ",
    .family = "CONVERT",
    .path = "CONVERT/CVTPS2DQ.inc",
    .source_table_path = "CONVERT/CVTPS2DQ.inc",
    .target_isa = .neon,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "CVTPS2DQ", .path = "CONVERT/CVTPS2DQ.inc", .encoding_count = 6, .source_path_len = 20 } },
    .{ .documented_contract = .{ .name = "CVTPS2DQ", .path = "CONVERT/CVTPS2DQ.inc", .encoding_count = 6, .source_path_len = 20 } },
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

test "neon CVTPS2DQ documented-contract proofs match table metadata" {
    try verifyProofs();
}
