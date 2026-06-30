const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");
pub const meta = core.InstructionMathMeta{ .name = "UD1", .family = "UNDEF", .path = "UNDEF/UD1.inc", .source_table_path = "UNDEF/UD1.inc", .target_isa = .neon, .operation = .documented_contract, .register_model = .documented_contract, .flag_model = .documented_contract };
pub const proof_cases = [_]proofs.ProofCase{.{ .documented_contract = .{ .name = "UD1", .path = "UNDEF/UD1.inc", .encoding_count = 1, .source_path_len = 13 } }};
pub const proof_report = proofs.ProofReport{ .meta = meta, .cases = proof_cases[0..] };
pub fn proofReport() proofs.ProofReport {
    return proof_report;
}
pub fn verifyProofs() !void {
    try proofs.verifyReport(proofReport());
}
test "NEON UD1 documented-contract proofs match table metadata" {
    try verifyProofs();
}
