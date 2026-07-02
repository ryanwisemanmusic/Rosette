const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");
pub const meta = core.InstructionMathMeta{ .name = "KXORB", .family = "KXOR", .path = "KXOR/KXORB.inc", .source_table_path = "KXOR/KXORB.inc", .target_isa = .neon, .operation = .documented_contract, .register_model = .documented_contract, .flag_model = .documented_contract };
pub const proof_cases = [_]proofs.ProofCase{.{ .documented_contract = .{ .name = "KXORB", .path = "KXOR/KXORB.inc", .encoding_count = 1, .source_path_len = 15 } }};
pub const proof_report = proofs.ProofReport{ .meta = meta, .cases = proof_cases[0..] };
pub fn proofReport() proofs.ProofReport {
    return proof_report;
}
pub fn verifyProofs() !void {
    try proofs.verifyReport(proofReport());
}
test "NEON KXORB documented-contract proofs match table metadata" {
    try verifyProofs();
}
