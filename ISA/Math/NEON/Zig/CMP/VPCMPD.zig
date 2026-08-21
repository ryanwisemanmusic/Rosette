const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "VPCMPD",
    .family = "CMP",
    .path = "CMP/VPCMPD.inc",
    .source_table_path = "CMP/VPCMPD.inc",
    .target_isa = .neon,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "VPCMPD", .path = "CMP/VPCMPD.inc", .encoding_count = 3, .source_path_len = 14 } },
    .{ .documented_contract = .{ .name = "VPCMPD", .path = "CMP/VPCMPD.inc", .encoding_count = 3, .source_path_len = 14 } },
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

test "neon VPCMPD documented-contract proofs match table metadata" {
    try verifyProofs();
}
