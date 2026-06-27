const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "VPSHRDVW",
    .family = "CONCATENATE",
    .path = "CONCATENATE/VPSHRDVW.inc",
    .source_table_path = "CONCATENATE/VPSHRDVW.inc",
    .target_isa = .neon,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "VPSHRDVW", .path = "CONCATENATE/VPSHRDVW.inc", .encoding_count = 3, .source_path_len = 22 } },
    .{ .documented_contract = .{ .name = "VPSHRDVW", .path = "CONCATENATE/VPSHRDVW.inc", .encoding_count = 3, .source_path_len = 22 } },
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

test "neon VPSHRDVW documented-contract proofs match table metadata" {
    try verifyProofs();
}
