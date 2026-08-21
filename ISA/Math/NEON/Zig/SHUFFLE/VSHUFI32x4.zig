const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");
pub const meta = core.InstructionMathMeta{ .name = "VSHUFI32x4", .family = "SHUFFLE", .path = "SHUFFLE/VSHUFI32x4.inc", .source_table_path = "SHUFFLE/VSHUFI32x4.inc", .target_isa = .neon, .operation = .documented_contract, .register_model = .documented_contract, .flag_model = .documented_contract };
pub const proof_cases = [_]proofs.ProofCase{.{ .documented_contract = .{ .name = "VSHUFI32x4", .path = "SHUFFLE/VSHUFI32x4.inc", .encoding_count = 2, .source_path_len = 22 } }};
pub const proof_report = proofs.ProofReport{ .meta = meta, .cases = proof_cases[0..] };
pub fn proofReport() proofs.ProofReport {
    return proof_report;
}
pub fn verifyProofs() !void {
    try proofs.verifyReport(proofReport());
}
test "NEON VSHUFI32x4 documented-contract proofs match table metadata" {
    try verifyProofs();
}
