const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "VFMADD231SS",
    .family = "FUSED",
    .path = "FUSED/VFMADD231SS.inc",
    .source_table_path = "FUSED/VFMADD231SS.inc",
    .target_isa = .x86,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "VFMADD231SS", .path = "FUSED/VFMADD231SS.inc", .encoding_count = 2, .source_path_len = 22 } },
    .{ .documented_contract = .{ .name = "VFMADD231SS", .path = "FUSED/VFMADD231SS.inc", .encoding_count = 2, .source_path_len = 22 } },
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

test "x86 VFMADD231SS documented-contract proofs match table metadata" {
    try verifyProofs();
}
