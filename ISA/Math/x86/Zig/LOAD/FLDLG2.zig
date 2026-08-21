const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "FLDLG2",
    .family = "LOAD",
    .path = "LOAD/FLDLG2.inc",
    .source_table_path = "LOAD/FLDLG2.inc",
    .target_isa = .x86,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "FLDLG2", .path = "LOAD/FLDLG2.inc", .encoding_count = 1, .source_path_len = 15 } },
    .{ .documented_contract = .{ .name = "FLDLG2", .path = "LOAD/FLDLG2.inc", .encoding_count = 1, .source_path_len = 15 } },
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

test "x86 FLDLG2 documented-contract proofs match table metadata" {
    try verifyProofs();
}
