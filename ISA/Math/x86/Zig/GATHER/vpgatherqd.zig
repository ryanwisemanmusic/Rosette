const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "VPGATHERQD",
    .family = "GATHER",
    .path = "GATHER/VPGATHERQD.inc",
    .source_table_path = "GATHER/VPGATHERQD.inc",
    .target_isa = .x86,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "VPGATHERQD", .path = "GATHER/VPGATHERQD.inc", .encoding_count = 5, .source_path_len = 21 } },
    .{ .documented_contract = .{ .name = "VPGATHERQD", .path = "GATHER/VPGATHERQD.inc", .encoding_count = 5, .source_path_len = 21 } },
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

test "x86 VPGATHERQD documented-contract proofs match table metadata" {
    try verifyProofs();
}
