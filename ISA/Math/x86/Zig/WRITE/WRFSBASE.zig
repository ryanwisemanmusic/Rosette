const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "WRFSBASE",
    .family = "WRITE",
    .path = "WRITE/WRFSBASE.inc",
    .source_table_path = "WRITE/WRFSBASE.inc",
    .target_isa = .x86,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "WRFSBASE", .path = "WRITE/WRFSBASE.inc", .encoding_count = 2, .source_path_len = 18 } },
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

test "x86 WRFSBASE documented-contract proofs match table metadata" {
    try verifyProofs();
}
