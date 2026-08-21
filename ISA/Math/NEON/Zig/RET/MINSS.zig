const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "MINSS",
    .family = "RET",
    .path = "RET/MINSS.inc",
    .source_table_path = "RET/MINSS.inc",
    .target_isa = .neon,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "MINSS", .path = "RET/MINSS.inc", .encoding_count = 3, .source_path_len = 13 } },
    .{ .documented_contract = .{ .name = "MINSS", .path = "RET/MINSS.inc", .encoding_count = 3, .source_path_len = 13 } },
    .{ .documented_contract = .{ .name = "MINSS", .path = "RET/MINSS.inc", .encoding_count = 3, .source_path_len = 13 } },
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

test "neon MINSS documented-contract proofs match table metadata" {
    try verifyProofs();
}
