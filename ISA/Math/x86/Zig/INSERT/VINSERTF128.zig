const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");
pub const meta = core.InstructionMathMeta{ .name = "VINSERTF128", .family = "INSERT", .path = "INSERT/VINSERTF128.inc", .source_table_path = "INSERT/VINSERTF128.inc", .target_isa = .x86, .operation = .documented_contract, .register_model = .documented_contract, .flag_model = .documented_contract };
pub const proof_cases = [_]proofs.ProofCase{.{ .documented_contract = .{ .name = "VINSERTF128", .path = "INSERT/VINSERTF128.inc", .encoding_count = 1, .source_path_len = 22 } }};
pub const proof_report = proofs.ProofReport{ .meta = meta, .cases = proof_cases[0..] };
pub fn proofReport() proofs.ProofReport {
    return proof_report;
}
pub fn verifyProofs() !void {
    try proofs.verifyReport(proofReport());
}
test "x86 VINSERTF128 documented-contract proofs match table metadata" {
    try verifyProofs();
}
