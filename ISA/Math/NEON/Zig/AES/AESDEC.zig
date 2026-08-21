const core = @import("../../../core.zig");
const proofs = @import("../../../proofs.zig");

pub const meta = core.InstructionMathMeta{
    .name = "AESDEC",
    .family = "AES",
    .path = "AES/AESDEC.inc",
    .source_table_path = "AES/AESDEC.inc",
    .target_isa = .neon,
    .operation = .documented_contract,
    .register_model = .documented_contract,
    .flag_model = .documented_contract,
};

pub const proof_cases = [_]proofs.ProofCase{
    .{ .documented_contract = .{ .name = "AESDEC", .path = "AES/AESDEC.inc", .encoding_count = 6, .source_path_len = 14 } },
    .{ .documented_contract = .{ .name = "AESDEC", .path = "AES/AESDEC.inc", .encoding_count = 6, .source_path_len = 14 } },
};

pub const proof_report = proofs.ProofReport{
    .meta = meta,
    .cases = proof_cases[0..],
};
