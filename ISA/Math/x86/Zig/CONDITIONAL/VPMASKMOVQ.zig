const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "VPMASKMOVQ",
    .family = "CONDITIONAL",
    .path = "CONDITIONAL/VPMASKMOVQ.inc",
    .source_table_path = "CONDITIONAL/VPMASKMOVQ.inc",
    .target_isa = .x86,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "VPMASKMOVQ", .path = "CONDITIONAL/VPMASKMOVQ.inc", .encoding_count = 4, .source_path_len = 26 } },
    .{ .documented_contract = .{ .name = "VPMASKMOVQ", .path = "CONDITIONAL/VPMASKMOVQ.inc", .encoding_count = 4, .source_path_len = 26 } },
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

test "x86 VPMASKMOVQ documented-contract proofs match table metadata" {
    try verifyProofs();
}
