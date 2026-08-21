const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "VFMADD132SD",
    .family = "FUSED",
    .path = "FUSED/VFMADD132SD.inc",
    .source_table_path = "FUSED/VFMADD132SD.inc",
    .target_isa = .x86,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "VFMADD132SD", .path = "FUSED/VFMADD132SD.inc", .encoding_count = 2, .source_path_len = 21 } },
    .{ .documented_contract = .{ .name = "VFMADD132SD", .path = "FUSED/VFMADD132SD.inc", .encoding_count = 2, .source_path_len = 21 } },
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

test "x86 VFMADD132SD documented-contract proofs match table metadata" {
    try verifyProofs();
}
