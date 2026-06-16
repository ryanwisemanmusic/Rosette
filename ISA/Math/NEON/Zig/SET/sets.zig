const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "SETS",
    .family = "SET",
    .path = "SET/SETS.inc",
    .source_table_path = "SET/SETS.inc",
    .target_isa = .neon,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "SETS", .path = "SET/SETS.inc", .encoding_count = 1, .source_path_len = 12 } },
    .{ .documented_contract = .{ .name = "SETS", .path = "SET/SETS.inc", .encoding_count = 1, .source_path_len = 12 } },
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

test "neon SETS documented-contract proofs match table metadata" {
    try verifyProofs();
}
