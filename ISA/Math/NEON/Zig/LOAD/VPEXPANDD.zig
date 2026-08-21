const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "VPEXPANDD",
    .family = "LOAD",
    .path = "LOAD/VPEXPANDD.inc",
    .source_table_path = "LOAD/VPEXPANDD.inc",
    .target_isa = .neon,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "VPEXPANDD", .path = "LOAD/VPEXPANDD.inc", .encoding_count = 3, .source_path_len = 18 } },
    .{ .documented_contract = .{ .name = "VPEXPANDD", .path = "LOAD/VPEXPANDD.inc", .encoding_count = 3, .source_path_len = 18 } },
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

test "neon VPEXPANDD documented-contract proofs match table metadata" {
    try verifyProofs();
}
