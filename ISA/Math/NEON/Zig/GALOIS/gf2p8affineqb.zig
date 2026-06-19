const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "GF2P8AFFINEQB",
    .family = "GALOIS",
    .path = "GALOIS/GF2P8AFFINEQB.inc",
    .source_table_path = "GALOIS/GF2P8AFFINEQB.inc",
    .target_isa = .neon,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "GF2P8AFFINEQB", .path = "GALOIS/GF2P8AFFINEQB.inc", .encoding_count = 3, .source_path_len = 24 } },
    .{ .documented_contract = .{ .name = "GF2P8AFFINEQB", .path = "GALOIS/GF2P8AFFINEQB.inc", .encoding_count = 3, .source_path_len = 24 } },
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

test "neon GF2P8AFFINEQB documented-contract proofs match table metadata" {
    try verifyProofs();
}

