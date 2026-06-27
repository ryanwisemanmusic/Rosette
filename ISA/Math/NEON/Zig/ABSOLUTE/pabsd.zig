const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "PABSD",
    .family = "ABSOLUTE",
    .path = "ABSOLUTE/PABSD.inc",
    .source_table_path = "ABSOLUTE/PABSD.inc",
    .target_isa = .neon,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "PABSD", .path = "ABSOLUTE/PABSD.inc", .encoding_count = 7, .source_path_len = 13 } },
    .{ .documented_contract = .{ .name = "PABSD", .path = "ABSOLUTE/PABSD.inc", .encoding_count = 7, .source_path_len = 13 } },
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

test "neon PABSD documented-contract proofs match table metadata" {
    try verifyProofs();
}
