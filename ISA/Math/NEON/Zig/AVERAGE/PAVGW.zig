const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "PAVGW",
    .family = "AVERAGE",
    .path = "AVERAGE/PAVGW.inc",
    .source_table_path = "AVERAGE/PAVGW.inc",
    .target_isa = .neon,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "PAVGW", .path = "AVERAGE/PAVGW.inc", .encoding_count = 7, .source_path_len = 17 } },
    .{ .documented_contract = .{ .name = "PAVGW", .path = "AVERAGE/PAVGW.inc", .encoding_count = 7, .source_path_len = 17 } },
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

test "NEON PAVGW documented-contract proofs match table metadata" {
    try verifyProofs();
}
