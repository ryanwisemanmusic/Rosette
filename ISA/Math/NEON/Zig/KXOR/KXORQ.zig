const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");
pub const meta = core.InstructionMathMeta{ .name = "KXORQ", .family = "KXOR", .path = "KXOR/KXORQ.inc", .source_table_path = "KXOR/KXORQ.inc", .target_isa = .neon, .operation = .documented_contract, .register_model = .documented_contract, .flag_model = .documented_contract };
pub const proof_cases = [_]proofs.ProofCase{.{ .documented_contract = .{ .name = "KXORQ", .path = "KXOR/KXORQ.inc", .encoding_count = 1, .source_path_len = 15 } }};
pub const proof_report = proofs.ProofReport{ .meta = meta, .cases = proof_cases[0..] };
pub fn proofReport() proofs.ProofReport {
    return proof_report;
}
pub fn verifyProofs() !void {
    try proofs.verifyReport(proofReport());
}
test "NEON KXORQ documented-contract proofs match table metadata" {
    try verifyProofs();
}
