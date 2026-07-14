const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "VFMSUB231SH",
    .family = "FUSED",
    .path = "FUSED/VFMSUB231SH.inc",
    .source_table_path = "FUSED/VFMSUB231SH.inc",
    .target_isa = .neon,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "VFMSUB231SH", .path = "FUSED/VFMSUB231SH.inc", .encoding_count = 1, .source_path_len = 21 } },
    .{ .documented_contract = .{ .name = "VFMSUB231SH", .path = "FUSED/VFMSUB231SH.inc", .encoding_count = 1, .source_path_len = 21 } },
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

test "neon VFMSUB231SH documented-contract proofs match table metadata" {
    try verifyProofs();
}
