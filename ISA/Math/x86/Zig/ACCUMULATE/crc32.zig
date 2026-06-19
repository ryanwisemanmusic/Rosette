const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "CRC32",
    .family = "ACCUMULATE",
    .path = "ACCUMULATE/CRC32.inc",
    .source_table_path = "ACCUMULATE/CRC32.inc",
    .target_isa = .x86,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "CRC32", .path = "ACCUMULATE/CRC32.inc", .encoding_count = 5, .source_path_len = 20 } },
    .{ .documented_contract = .{ .name = "CRC32", .path = "ACCUMULATE/CRC32.inc", .encoding_count = 5, .source_path_len = 20 } },
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

test "x86 CRC32 documented-contract proofs match table metadata" {
    try verifyProofs();
}

