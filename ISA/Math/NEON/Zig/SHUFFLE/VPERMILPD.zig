const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "VPERMILPD",
    .family = "SHUFFLE",
    .path = "SHUFFLE/VPERMILPD.inc",
    .source_table_path = "SHUFFLE/VPERMILPD.inc",
    .target_isa = .neon,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "VPERMILPD", .path = "SHUFFLE/VPERMILPD.inc", .encoding_count = 2, .source_path_len = 21 } },
    .{ .documented_contract = .{ .name = "VPERMILPD", .path = "SHUFFLE/VPERMILPD.inc", .encoding_count = 2, .source_path_len = 21 } },
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

test "NEON VPERMILPD documented-contract proofs match table metadata" {
    try verifyProofs();
}
