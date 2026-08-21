const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "AESENCWIDE128KL",
    .family = "AES",
    .path = "AES/AESENCWIDE128KL.inc",
    .source_table_path = "AES/AESENCWIDE128KL.inc",
    .target_isa = .x86,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "AESENCWIDE128KL", .path = "AES/AESENCWIDE128KL.inc", .encoding_count = 1, .source_path_len = 23 } },
    .{ .documented_contract = .{ .name = "AESENCWIDE128KL", .path = "AES/AESENCWIDE128KL.inc", .encoding_count = 1, .source_path_len = 23 } },
};

pub const proof_report = proofs.ProofReport{
    .meta = meta,
    .cases = proof_cases[0..],
};
