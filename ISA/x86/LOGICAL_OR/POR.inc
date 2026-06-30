// LOGICAL_OR/POR.inc
// Source contract: POR — Bitwise Logical OR (MMX/SSE2).

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "LOGICAL_OR/POR.inc"
x86_handler = "x86_por"
neon_lowering = "arm64_por"
lowering_kind = "arm64_documented_contract"

name = "POR"
aliases = []
category = "simd_logical"
feature = "mmx"

encodings = [
  { opcode = "NP 0F EB /r", form = "POR mm, mm/m64", op_en = "A", feature = "mmx", vector_length = 64, encoding = "legacy" },
  { opcode = "66 0F EB /r", form = "POR xmm1, xmm2/m128", op_en = "A", feature = "sse2", vector_length = 128, encoding = "legacy" }
]

operand_encoding = {
  A = ["ModRM:reg (r, w)", "ModRM:r/m (r)", "N/A", "N/A"]
}

lanes = { dword = 1 }
flags_written = []
floating_point_exceptions = []
other_exceptions = ["Non-EVEX-encoded instruction, see Table 2-21, Type 4 Class Exception Conditions."]

semantic_general = "Performs a bitwise logical OR operation on the source and destination operands; each bit is set to 1 if either corresponding bit is 1."

handler = "x86_por"
jit_lowering = "arm64_por"
fallback = "zig_por"

neon_register_model = "POR is an SSE/MMX bitwise OR instruction."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: POR stub"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
