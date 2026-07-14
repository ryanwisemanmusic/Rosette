const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "VFMSUBADD231PD",
    .family = "FUSED",
    .path = "FUSED/VFMSUBADD231PD.inc",
    .source_table_path = "FUSED/VFMSUBADD231PD.inc",
    .target_isa = .x86,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "VFMSUBADD231PD", .path = "FUSED/VFMSUBADD231PD.inc", .encoding_count = 5, .source_path_len = 23 } },
    .{ .documented_contract = .{ .name = "VFMSUBADD231PD", .path = "FUSED/VFMSUBADD231PD.inc", .encoding_count = 5, .source_path_len = 23 } },
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

test "x86 VFMSUBADD231PD documented-contract proofs match table metadata" {
    try verifyProofs();
}
