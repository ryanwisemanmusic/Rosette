const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "PREFETCHW",
    .family = "PREFETCH",
    .path = "PREFETCH/PREFETCHW.inc",
    .source_table_path = "PREFETCH/PREFETCHW.inc",
    .target_isa = .neon,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "PREFETCHW", .path = "PREFETCH/PREFETCHW.inc", .encoding_count = 1, .source_path_len = 22 } },
    .{ .documented_contract = .{ .name = "PREFETCHW", .path = "PREFETCH/PREFETCHW.inc", .encoding_count = 1, .source_path_len = 22 } },
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

test "neon PREFETCHW documented-contract proofs match table metadata" {
    try verifyProofs();
}
