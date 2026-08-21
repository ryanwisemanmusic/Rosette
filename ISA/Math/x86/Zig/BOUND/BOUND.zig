const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "BOUND",
    .family = "BOUND",
    .path = "BOUND/BOUND.inc",
    .source_table_path = "BOUND/BOUND.inc",
    .target_isa = .x86,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "BOUND", .path = "BOUND/BOUND.inc", .encoding_count = 2, .source_path_len = 15 } },
    .{ .documented_contract = .{ .name = "BOUND", .path = "BOUND/BOUND.inc", .encoding_count = 2, .source_path_len = 15 } },
};

pub const proof_report = proofs.ProofReport{
    .meta = meta,
    .cases = proof_cases[0..],
};
