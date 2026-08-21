const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "FUCOMPP",
    .family = "X87_FPU",
    .path = "X87_FPU/FUCOMPP.inc",
    .source_table_path = "X87_FPU/FUCOMPP.inc",
    .target_isa = .neon,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "FUCOMPP", .path = "X87_FPU/FUCOMPP.inc", .encoding_count = 1, .source_path_len = 19 } },
    .{ .documented_contract = .{ .name = "FUCOMPP", .path = "X87_FPU/FUCOMPP.inc", .encoding_count = 1, .source_path_len = 19 } },
};

pub const proof_report = proofs.ProofReport{
    .meta = meta,
    .cases = proof_cases[0..],
};
