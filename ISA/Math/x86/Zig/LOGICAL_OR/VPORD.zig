const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");
pub const meta = core.InstructionMathMeta{ .name = "VPORD", .family = "LOGICAL_OR", .path = "LOGICAL_OR/VPORD.inc", .source_table_path = "LOGICAL_OR/VPORD.inc", .target_isa = .x86, .operation = .documented_contract, .register_model = .documented_contract, .flag_model = .documented_contract };
pub const proof_cases = [_]proofs.ProofCase{.{ .documented_contract = .{ .name = "VPORD", .path = "LOGICAL_OR/VPORD.inc", .encoding_count = 3, .source_path_len = 20 } }};
pub const proof_report = proofs.ProofReport{ .meta = meta, .cases = proof_cases[0..] };
pub fn proofReport() proofs.ProofReport { return proof_report; }
pub fn verifyProofs() !void { try proofs.verifyReport(proofReport()); }
test "x86 VPORD documented-contract proofs match table metadata" { try verifyProofs(); }
