const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "VFMSUBADD132PS",
    .family = "FUSED",
    .path = "FUSED/VFMSUBADD132PS.inc",
    .source_table_path = "FUSED/VFMSUBADD132PS.inc",
    .target_isa = .x86,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "VFMSUBADD132PS", .path = "FUSED/VFMSUBADD132PS.inc", .encoding_count = 5, .source_path_len = 24 } },
    .{ .documented_contract = .{ .name = "VFMSUBADD132PS", .path = "FUSED/VFMSUBADD132PS.inc", .encoding_count = 5, .source_path_len = 24 } },
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

test "x86 VFMSUBADD132PS documented-contract proofs match table metadata" {
    try verifyProofs();
}
