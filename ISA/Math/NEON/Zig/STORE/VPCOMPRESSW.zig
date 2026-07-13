const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "VPCOMPRESSW",
    .family = "STORE",
    .path = "STORE/VPCOMPRESSW.inc",
    .source_table_path = "STORE/VPCOMPRESSW.inc",
    .target_isa = .neon,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "VPCOMPRESSW", .path = "STORE/VPCOMPRESSW.inc", .encoding_count = 6, .source_path_len = 15 } },
    .{ .documented_contract = .{ .name = "VPCOMPRESSW", .path = "STORE/VPCOMPRESSW.inc", .encoding_count = 6, .source_path_len = 15 } },
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

test "neon VPCOMPRESSW documented-contract proofs match table metadata" {
    try verifyProofs();
}
