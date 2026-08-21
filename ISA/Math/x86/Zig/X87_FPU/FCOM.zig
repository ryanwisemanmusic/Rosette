const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "FCOM",
    .family = "X87_FPU",
    .path = "X87_FPU/FCOM.inc",
    .source_table_path = "X87_FPU/FCOM.inc",
    .target_isa = .x86,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "FCOM", .path = "X87_FPU/FCOM.inc", .encoding_count = 4, .source_path_len = 16 } },
    .{ .documented_contract = .{ .name = "FCOM", .path = "X87_FPU/FCOM.inc", .encoding_count = 4, .source_path_len = 16 } },
};

pub const proof_report = proofs.ProofReport{
    .meta = meta,
    .cases = proof_cases[0..],
};
