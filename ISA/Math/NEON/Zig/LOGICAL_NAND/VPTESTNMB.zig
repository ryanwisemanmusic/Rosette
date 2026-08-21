const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "VPTESTNMB",
    .family = "LOGICAL_NAND",
    .path = "LOGICAL_NAND/VPTESTNMB.inc",
    .source_table_path = "LOGICAL_NAND/VPTESTNMB.inc",
    .target_isa = .neon,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "VPTESTNMB", .path = "LOGICAL_NAND/VPTESTNMB.inc", .encoding_count = 3, .source_path_len = 26 } },
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

test "NEON VPTESTNMB documented-contract proofs match table metadata" {
    try verifyProofs();
}
