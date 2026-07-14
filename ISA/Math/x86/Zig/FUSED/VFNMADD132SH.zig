const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "VFNMADD132SH",
    .family = "FUSED",
    .path = "FUSED/VFNMADD132SH.inc",
    .source_table_path = "FUSED/VFNMADD132SH.inc",
    .target_isa = .x86,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "VFNMADD132SH", .path = "FUSED/VFNMADD132SH.inc", .encoding_count = 1, .source_path_len = 23 } },
    .{ .documented_contract = .{ .name = "VFNMADD132SH", .path = "FUSED/VFNMADD132SH.inc", .encoding_count = 1, .source_path_len = 23 } },
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

test "x86 VFNMADD132SH documented-contract proofs match table metadata" {
    try verifyProofs();
}
