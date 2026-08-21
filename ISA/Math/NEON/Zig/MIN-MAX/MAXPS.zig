const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");
pub const meta = core.InstructionMathMeta{ .name = "MAXPS", .family = "MIN-MAX", .path = "MIN-MAX/MAXPS.inc", .source_table_path = "MIN-MAX/MAXPS.inc", .target_isa = .neon, .operation = .documented_contract, .register_model = .documented_contract, .flag_model = .documented_contract };
pub const proof_cases = [_]proofs.ProofCase{.{ .documented_contract = .{ .name = "MAXPS", .path = "MIN-MAX/MAXPS.inc", .encoding_count = 6, .source_path_len = 17 } }};
pub const proof_report = proofs.ProofReport{ .meta = meta, .cases = proof_cases[0..] };
pub fn proofReport() proofs.ProofReport {
    return proof_report;
}
pub fn verifyProofs() !void {
    try proofs.verifyReport(proofReport());
}
test "NEON MAXPS documented-contract proofs match table metadata" {
    try verifyProofs();
}
