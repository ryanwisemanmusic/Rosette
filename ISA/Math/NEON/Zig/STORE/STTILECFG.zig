const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "STTILECFG",
    .family = "STORE",
    .path = "STORE/STTILECFG.inc",
    .source_table_path = "STORE/STTILECFG.inc",
    .target_isa = .neon,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "STTILECFG", .path = "STORE/STTILECFG.inc", .encoding_count = 1, .source_path_len = 19 } },
    .{ .documented_contract = .{ .name = "STTILECFG", .path = "STORE/STTILECFG.inc", .encoding_count = 1, .source_path_len = 19 } },
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

test "neon STORE/STTILECFG documented-contract proofs match table metadata" {
    try verifyProofs();
}
