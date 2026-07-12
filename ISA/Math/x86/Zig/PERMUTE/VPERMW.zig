const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "VPERMW",
    .family = "PERMUTE",
    .path = "PERMUTE/VPERMW.inc",
    .source_table_path = "PERMUTE/VPERMW.inc",
    .target_isa = .x86,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "VPERMW", .path = "PERMUTE/VPERMW.inc", .encoding_count = 3, .source_path_len = 12 } },
    .{ .documented_contract = .{ .name = "VPERMW", .path = "PERMUTE/VPERMW.inc", .encoding_count = 3, .source_path_len = 12 } },
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

test "x86 VPERMW documented-contract proofs match table metadata" {
    try verifyProofs();
}
