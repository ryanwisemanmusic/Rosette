const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "BNDMOV",
    .family = "BOUND",
    .path = "BOUND/BNDMOV.inc",
    .source_table_path = "BOUND/BNDMOV.inc",
    .target_isa = .neon,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "BNDMOV", .path = "BOUND/BNDMOV.inc", .encoding_count = 4, .source_path_len = 16 } },
    .{ .documented_contract = .{ .name = "BNDMOV", .path = "BOUND/BNDMOV.inc", .encoding_count = 4, .source_path_len = 16 } },
};

pub const proof_report = proofs.ProofReport{
    .meta = meta,
    .cases = proof_cases[0..],
};
