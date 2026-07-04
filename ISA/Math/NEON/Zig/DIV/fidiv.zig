const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "FIDIV",
    .family = "DIV",
    .path = "DIV/FIDIV.inc",
    .source_table_path = "DIV/FIDIV.inc",
    .target_isa = .neon,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "FIDIV", .path = "DIV/FIDIV.inc", .encoding_count = 2, .source_path_len = 13 } },
    .{ .documented_contract = .{ .name = "FIDIV", .path = "DIV/FIDIV.inc", .encoding_count = 2, .source_path_len = 13 } },
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

test "neon FIDIV documented-contract proofs match table metadata" {
    try verifyProofs();
}
