const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "VBROADCASTF64X4",
    .family = "LOAD",
    .path = "LOAD/VBROADCASTF64X4.inc",
    .source_table_path = "LOAD/VBROADCASTF64X4.inc",
    .target_isa = .x86,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "VBROADCASTF64X4", .path = "LOAD/VBROADCASTF64X4.inc", .encoding_count = 1, .source_path_len = 24 } },
    .{ .documented_contract = .{ .name = "VBROADCASTF64X4", .path = "LOAD/VBROADCASTF64X4.inc", .encoding_count = 1, .source_path_len = 24 } },
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

test "x86 VBROADCASTF64X4 documented-contract proofs match table metadata" {
    try verifyProofs();
}
