const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "VFMADDSUB213PH",
    .family = "FUSED",
    .path = "FUSED/VFMADDSUB213PH.inc",
    .source_table_path = "FUSED/VFMADDSUB213PH.inc",
    .target_isa = .neon,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "VFMADDSUB213PH", .path = "FUSED/VFMADDSUB213PH.inc", .encoding_count = 3, .source_path_len = 24 } },
    .{ .documented_contract = .{ .name = "VFMADDSUB213PH", .path = "FUSED/VFMADDSUB213PH.inc", .encoding_count = 3, .source_path_len = 24 } },
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

test "neon VFMADDSUB213PH documented-contract proofs match table metadata" {
    try verifyProofs();
}
