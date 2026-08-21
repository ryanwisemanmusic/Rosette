const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "AESDECLAST",
    .family = "AES",
    .path = "AES/AESDECLAST.inc",
    .source_table_path = "AES/AESDECLAST.inc",
    .target_isa = .neon,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "AESDECLAST", .path = "AES/AESDECLAST.inc", .encoding_count = 6, .source_path_len = 18 } },
    .{ .documented_contract = .{ .name = "AESDECLAST", .path = "AES/AESDECLAST.inc", .encoding_count = 6, .source_path_len = 18 } },
};

pub const proof_report = proofs.ProofReport{
    .meta = meta,
    .cases = proof_cases[0..],
};
