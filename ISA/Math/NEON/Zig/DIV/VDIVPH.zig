const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "VDIVPH",
    .family = "DIV",
    .path = "DIV/VDIVPH.inc",
    .source_table_path = "DIV/VDIVPH.inc",
    .target_isa = .neon,
    .operation = .divpd,
    .register_model = .simd_packed,
    .flag_model = .mxcsr_float,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .divpd = .{ .lhs = .{ 6.0, -9.0 }, .rhs = .{ 2.0, 3.0 }, .expected = .{ 3.0, -3.0 } } },
    .{ .divpd = .{ .lhs = .{ 10.0, 1.0 }, .rhs = .{ 2.0, 4.0 }, .expected = .{ 5.0, 0.25 } } },
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

test "neon VDIVPH hardcoded math proofs match core" {
    try verifyProofs();
}
