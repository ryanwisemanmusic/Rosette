const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "SETNL",
    .family = "SET",
    .path = "SET/SETNL.inc",
    .source_table_path = "SET/SETNL.inc",
    .target_isa = .neon,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "SETNL", .path = "SET/SETNL.inc", .encoding_count = 1, .source_path_len = 13 } },
    .{ .documented_contract = .{ .name = "SETNL", .path = "SET/SETNL.inc", .encoding_count = 1, .source_path_len = 13 } },
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

test "neon SETNL documented-contract proofs match table metadata" {
    try verifyProofs();
}
