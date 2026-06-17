const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "VPEXPANDW",
    .family = "EXPAND",
    .path = "EXPAND/VPEXPANDW.inc",
    .source_table_path = "EXPAND/VPEXPANDW.inc",
    .target_isa = .neon,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "VPEXPANDW", .path = "EXPAND/VPEXPANDW.inc", .encoding_count = 6, .source_path_len = 20 } },
    .{ .documented_contract = .{ .name = "VPEXPANDW", .path = "EXPAND/VPEXPANDW.inc", .encoding_count = 6, .source_path_len = 20 } },
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

test "neon VPEXPANDW documented-contract proofs match table metadata" {
    try verifyProofs();
}
