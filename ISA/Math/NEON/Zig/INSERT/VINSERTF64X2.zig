const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");
pub const meta = core.InstructionMathMeta{ .name = "VINSERTF64X2", .family = "INSERT", .path = "INSERT/VINSERTF64X2.inc", .source_table_path = "INSERT/VINSERTF64X2.inc", .target_isa = .neon, .operation = .documented_contract, .register_model = .documented_contract, .flag_model = .documented_contract };
pub const proof_cases = [_]proofs.ProofCase{.{ .documented_contract = .{ .name = "VINSERTF64X2", .path = "INSERT/VINSERTF64X2.inc", .encoding_count = 2, .source_path_len = 23 } }};
pub const proof_report = proofs.ProofReport{ .meta = meta, .cases = proof_cases[0..] };
pub fn proofReport() proofs.ProofReport {
    return proof_report;
}
pub fn verifyProofs() !void {
    try proofs.verifyReport(proofReport());
}
test "NEON VINSERTF64X2 documented-contract proofs match table metadata" {
    try verifyProofs();
}
