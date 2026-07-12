const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "PUNPCKLWD",
    .family = "UNPACK",
    .path = "UNPACK/PUNPCKLWD.inc",
    .source_table_path = "UNPACK/PUNPCKLWD.inc",
    .target_isa = .x86,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "PUNPCKLWD", .path = "UNPACK/PUNPCKLWD.inc", .encoding_count = 7, .source_path_len = 17 } },
    .{ .documented_contract = .{ .name = "PUNPCKLWD", .path = "UNPACK/PUNPCKLWD.inc", .encoding_count = 7, .source_path_len = 17 } },
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

test "x86 PUNPCKLWD documented-contract proofs match table metadata" {
    try verifyProofs();
}
