const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "VFMADDSUB231PD",
    .family = "FUSED",
    .path = "FUSED/VFMADDSUB231PD.inc",
    .source_table_path = "FUSED/VFMADDSUB231PD.inc",
    .target_isa = .x86,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "VFMADDSUB231PD", .path = "FUSED/VFMADDSUB231PD.inc", .encoding_count = 5, .source_path_len = 24 } },
    .{ .documented_contract = .{ .name = "VFMADDSUB231PD", .path = "FUSED/VFMADDSUB231PD.inc", .encoding_count = 5, .source_path_len = 24 } },
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

test "x86 VFMADDSUB231PD documented-contract proofs match table metadata" {
    try verifyProofs();
}
