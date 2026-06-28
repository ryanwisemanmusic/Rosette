const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "MPSADBW",
    .family = "COMPUTE",
    .path = "COMPUTE/MPSADBW.inc",
    .source_table_path = "COMPUTE/MPSADBW.inc",
    .target_isa = .x86,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "MPSADBW", .path = "COMPUTE/MPSADBW.inc", .encoding_count = 3, .source_path_len = 18 } },
    .{ .documented_contract = .{ .name = "MPSADBW", .path = "COMPUTE/MPSADBW.inc", .encoding_count = 3, .source_path_len = 18 } },
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

test "x86 MPSADBW documented-contract proofs match table metadata" {
    try verifyProofs();
}
