const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "CVTSI2SD",
    .family = "CONVERT",
    .path = "CONVERT/CVTSI2SD.inc",
    .source_table_path = "CONVERT/CVTSI2SD.inc",
    .target_isa = .neon,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "CVTSI2SD", .path = "CONVERT/CVTSI2SD.inc", .encoding_count = 6, .source_path_len = 20 } },
    .{ .documented_contract = .{ .name = "CVTSI2SD", .path = "CONVERT/CVTSI2SD.inc", .encoding_count = 6, .source_path_len = 20 } },
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

test "neon CVTSI2SD documented-contract proofs match table metadata" {
    try verifyProofs();
}
