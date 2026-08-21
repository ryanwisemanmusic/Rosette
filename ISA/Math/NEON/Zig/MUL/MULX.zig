const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "MULX",
    .family = "MUL",
    .path = "MUL/MULX.inc",
    .source_table_path = "MUL/MULX.inc",
    .target_isa = .neon,
    .operation = .mulx,
    .register_model = .gpr_binary,
    .flag_model = .no_flags,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .mulx = .{ .width = .bits16, .lhs = 0xffff, .rhs = 2, .expected = .{ .dest = 0xfffe, .high = 1 } } },
    .{ .mulx = .{ .width = .bits8, .lhs = 2, .rhs = 3, .expected = .{ .dest = 6, .high = 0 } } },
    .{ .mulx = .{ .width = .bits32, .lhs = 0x10000, .rhs = 0x10000, .expected = .{ .dest = 0, .high = 1 } } },
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

test "neon MULX hardcoded math proofs match core" {
    try verifyProofs();
}
