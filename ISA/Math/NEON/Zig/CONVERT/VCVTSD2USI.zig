const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "VCVTSD2USI",
    .family = "CONVERT",
    .path = "CONVERT/VCVTSD2USI.inc",
    .source_table_path = "CONVERT/VCVTSD2USI.inc",
    .target_isa = .neon,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "VCVTSD2USI", .path = "CONVERT/VCVTSD2USI.inc", .encoding_count = 2, .source_path_len = 22 } },
    .{ .documented_contract = .{ .name = "VCVTSD2USI", .path = "CONVERT/VCVTSD2USI.inc", .encoding_count = 2, .source_path_len = 22 } },
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

test "neon VCVTSD2USI documented-contract proofs match table metadata" {
    try verifyProofs();
}
