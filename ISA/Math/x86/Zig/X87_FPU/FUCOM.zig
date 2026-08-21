const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "FUCOM",
    .family = "X87_FPU",
    .path = "X87_FPU/FUCOM.inc",
    .source_table_path = "X87_FPU/FUCOM.inc",
    .target_isa = .x86,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "FUCOM", .path = "X87_FPU/FUCOM.inc", .encoding_count = 2, .source_path_len = 17 } },
    .{ .documented_contract = .{ .name = "FUCOM", .path = "X87_FPU/FUCOM.inc", .encoding_count = 2, .source_path_len = 17 } },
};

pub const proof_report = proofs.ProofReport{
    .meta = meta,
    .cases = proof_cases[0..],
};
