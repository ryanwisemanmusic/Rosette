const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "AESENC256KL",
    .family = "AES",
    .path = "AES/AESENC256KL.inc",
    .source_table_path = "AES/AESENC256KL.inc",
    .target_isa = .x86,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "AESENC256KL", .path = "AES/AESENC256KL.inc", .encoding_count = 1, .source_path_len = 19 } },
    .{ .documented_contract = .{ .name = "AESENC256KL", .path = "AES/AESENC256KL.inc", .encoding_count = 1, .source_path_len = 19 } },
};

pub const proof_report = proofs.ProofReport{
    .meta = meta,
    .cases = proof_cases[0..],
};
