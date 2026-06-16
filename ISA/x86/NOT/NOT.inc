// NOT/NOT.inc
// Source contract: NOT — bitwise.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "NOT/NOT.inc"
x86_handler = "x86_not"
neon_lowering = "arm64_not"
lowering_kind = "arm64_documented_contract"

name = "NOT"
aliases = []
category = "bitwise"
feature = "x86_gpr"
element_type = "u8_u16_u32_u64"
element_size = 8

encodings = [
  { opcode = "F6 /2", form = "NOT r/m8", op_en = "M", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "REX + F6 /2", form = "NOT r/m8*", op_en = "M", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "F7 /2", form = "NOT r/m16", op_en = "M", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "F7 /2", form = "NOT r/m32", op_en = "M", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "REX.W + F7 /2", form = "NOT r/m64", op_en = "M", feature = "x86_gpr", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  M = ["ModRM:r/m (r, w)"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
Performs a bitwise NOT operation (one's complement negation).
"""

handler = "x86_not"
jit_lowering = "arm64_not"
fallback = "zig_not"

neon_register_model = """
NOT is a bitwise instruction. ARM64 MVN/BIC available.
"""

neon_flag_model = """
No x86 flags modified by NOT.
"""

neon_assembly = """
// NEON lowering: MVN instruction on ARM64
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, and notes above are intentionally preserved as the source contract."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
