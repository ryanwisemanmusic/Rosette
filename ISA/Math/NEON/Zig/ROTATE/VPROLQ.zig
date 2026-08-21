const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");
pub const meta = core.InstructionMathMeta{ .name = "VPROLQ", .family = "ROTATE", .path = "ROTATE/VPROLQ.inc", .source_table_path = "ROTATE/VPROLQ.inc", .target_isa = .neon, .operation = .documented_contract, .register_model = .documented_contract, .flag_model = .documented_contract };
pub const proof_cases = [_]proofs.ProofCase{.{ .documented_contract = .{ .name = "VPROLQ", .path = "ROTATE/VPROLQ.inc", .encoding_count = 3, .source_path_len = 17 } }};
pub const proof_report = proofs.ProofReport{ .meta = meta, .cases = proof_cases[0..] };
pub fn proofReport() proofs.ProofReport { return proof_report; }
pub fn verifyProofs() !void { try proofs.verifyReport(proofReport()); }
test "NEON VPROLQ documented-contract proofs match table metadata" { try verifyProofs(); }
