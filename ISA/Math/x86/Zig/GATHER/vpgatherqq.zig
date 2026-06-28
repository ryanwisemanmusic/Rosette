const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "VPGATHERQQ",
    .family = "GATHER",
    .path = "GATHER/VPGATHERQQ.inc",
    .source_table_path = "GATHER/VPGATHERQQ.inc",
    .target_isa = .x86,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "VPGATHERQQ", .path = "GATHER/VPGATHERQQ.inc", .encoding_count = 5, .source_path_len = 20 } },
    .{ .documented_contract = .{ .name = "VPGATHERQQ", .path = "GATHER/VPGATHERQQ.inc", .encoding_count = 5, .source_path_len = 20 } },
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

test "x86 VPGATHERQQ documented-contract proofs match table metadata" {
    try verifyProofs();
}
