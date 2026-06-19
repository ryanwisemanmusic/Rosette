const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "ENCODEKEY128",
    .family = "ENCODE",
    .path = "ENCODE/ENCODEKEY128.inc",
    .source_table_path = "ENCODE/ENCODEKEY128.inc",
    .target_isa = .x86,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "ENCODEKEY128", .path = "ENCODE/ENCODEKEY128.inc", .encoding_count = 1, .source_path_len = 23 } },
    .{ .documented_contract = .{ .name = "ENCODEKEY128", .path = "ENCODE/ENCODEKEY128.inc", .encoding_count = 1, .source_path_len = 23 } },
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

test "x86 ENCODEKEY128 documented-contract proofs match table metadata" {
    try verifyProofs();
}

