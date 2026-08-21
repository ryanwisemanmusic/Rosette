const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");
pub const meta = core.InstructionMathMeta{ .name = "VSCALEFSH", .family = "SCALE", .path = "SCALE/VSCALEFSH.inc", .source_table_path = "SCALE/VSCALEFSH.inc", .target_isa = .neon, .operation = .documented_contract, .register_model = .documented_contract, .flag_model = .documented_contract };
pub const proof_cases = [_]proofs.ProofCase{.{ .documented_contract = .{ .name = "VSCALEFSH", .path = "SCALE/VSCALEFSH.inc", .encoding_count = 1, .source_path_len = 19 } }};
pub const proof_report = proofs.ProofReport{ .meta = meta, .cases = proof_cases[0..] };
pub fn proofReport() proofs.ProofReport {
    return proof_report;
}
pub fn verifyProofs() !void {
    try proofs.verifyReport(proofReport());
}
test "NEON VSCALEFSH documented-contract proofs match table metadata" {
    try verifyProofs();
}
