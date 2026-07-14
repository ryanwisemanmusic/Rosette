const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "VFNMSUB132PH",
    .family = "FUSED",
    .path = "FUSED/VFNMSUB132PH.inc",
    .source_table_path = "FUSED/VFNMSUB132PH.inc",
    .target_isa = .x86,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "VFNMSUB132PH", .path = "FUSED/VFNMSUB132PH.inc", .encoding_count = 3, .source_path_len = 22 } },
    .{ .documented_contract = .{ .name = "VFNMSUB132PH", .path = "FUSED/VFNMSUB132PH.inc", .encoding_count = 3, .source_path_len = 22 } },
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

test "x86 VFNMSUB132PH documented-contract proofs match table metadata" {
    try verifyProofs();
}
