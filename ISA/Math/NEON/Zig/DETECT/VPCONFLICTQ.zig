const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "VPCONFLICTQ",
    .family = "DETECT",
    .path = "DETECT/VPCONFLICTQ.inc",
    .source_table_path = "DETECT/VPCONFLICTQ.inc",
    .target_isa = .neon,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "VPCONFLICTQ", .path = "DETECT/VPCONFLICTQ.inc", .encoding_count = 3, .source_path_len = 22 } },
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

test "NEON VPCONFLICTQ documented-contract proofs match table metadata" {
    try verifyProofs();
}
