const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "VFIXUPIMMSS",
    .family = "FIX_UP",
    .path = "FIX_UP/VFIXUPIMMSS.inc",
    .source_table_path = "FIX_UP/VFIXUPIMMSS.inc",
    .target_isa = .x86,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "VFIXUPIMMSS", .path = "FIX_UP/VFIXUPIMMSS.inc", .encoding_count = 1, .source_path_len = 23 } },
    .{ .documented_contract = .{ .name = "VFIXUPIMMSS", .path = "FIX_UP/VFIXUPIMMSS.inc", .encoding_count = 1, .source_path_len = 23 } },
};

pub const proof_report = proofs.ProofReport{
    .meta = meta,
    .cases = proof_cases[0..],
};

pub fn proofReport() proofs.ProofReport {
    return proof_report;
}

pub fn verifyProofs() !void {
    try proofs.verifyReport(proofReport());
}

test "x86 VFIXUPIMMSS documented-contract proofs match table metadata" {
    try verifyProofs();
}
