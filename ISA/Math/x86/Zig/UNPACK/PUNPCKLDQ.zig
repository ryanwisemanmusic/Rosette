const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "PUNPCKLDQ",
    .family = "UNPACK",
    .path = "UNPACK/PUNPCKLDQ.inc",
    .source_table_path = "UNPACK/PUNPCKLDQ.inc",
    .target_isa = .x86,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "PUNPCKLDQ", .path = "UNPACK/PUNPCKLDQ.inc", .encoding_count = 7, .source_path_len = 20 } },
    .{ .documented_contract = .{ .name = "PUNPCKLDQ", .path = "UNPACK/PUNPCKLDQ.inc", .encoding_count = 7, .source_path_len = 20 } },
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

test "x86 PUNPCKLDQ documented-contract proofs match table metadata" {
    try verifyProofs();
}
