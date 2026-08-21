const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "PSLLW",
    .family = "SHIFT",
    .path = "SHIFT/PSLLW.inc",
    .source_table_path = "SHIFT/PSLLW.inc",
    .target_isa = .neon,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "PSLLW", .path = "SHIFT/PSLLW.inc", .encoding_count = 14, .source_path_len = 15 } },
    .{ .documented_contract = .{ .name = "PSLLW", .path = "SHIFT/PSLLW.inc", .encoding_count = 14, .source_path_len = 15 } },
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

test "neon PSLLW documented-contract proofs match table metadata" {
    try verifyProofs();
}
