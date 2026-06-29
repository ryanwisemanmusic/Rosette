const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "VPBROADCASTMW2D",
    .family = "BROADCAST",
    .path = "BROADCAST/VPBROADCASTMW2D.inc",
    .source_table_path = "BROADCAST/VPBROADCASTMW2D.inc",
    .target_isa = .neon,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "VPBROADCASTMW2D", .path = "BROADCAST/VPBROADCASTMW2D.inc", .encoding_count = 3, .source_path_len = 26 } },
    .{ .documented_contract = .{ .name = "VPBROADCASTMW2D", .path = "BROADCAST/VPBROADCASTMW2D.inc", .encoding_count = 3, .source_path_len = 26 } },
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

test "NEON VPBROADCASTMW2D documented-contract proofs match table metadata" {
    try verifyProofs();
}
