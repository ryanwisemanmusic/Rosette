// COUNT/LZCNT.inc
// Source contract: LZCNT — bit_count.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "COUNT/LZCNT.inc"
x86_handler = "x86_lzcnt"
neon_lowering = "arm64_lzcnt"
lowering_kind = "arm64_documented_contract"

name = "LZCNT"
aliases = []
category = "bit_count"
feature = "LZCNT"
element_type = "u16_u32_u64"
element_size = 16

encodings = [
  { opcode = "F3 0F BD /r", form = "LZCNT r16, r/m16", op_en = "RM", feature = "LZCNT", vector_length = 0, encoding = "legacy" },
  { opcode = "F3 0F BD /r", form = "LZCNT r32, r/m32", op_en = "RM", feature = "LZCNT", vector_length = 0, encoding = "legacy" },
  { opcode = "F3 REX.W 0F BD /r", form = "LZCNT r64, r/m64", op_en = "RM", feature = "LZCNT", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  RM = ["ModRM:reg (w)", "ModRM:r/m (r)"]
}

flags_written = ["CF", "ZF"]
simd_fp_exceptions = []

semantic_general = """
Count the number of leading zero bits in the source operand and store the result in the destination.
"""

handler = "x86_lzcnt"
jit_lowering = "arm64_lzcnt"
fallback = "zig_lzcnt"

neon_register_model = """
x86 GPR/XMM/YMM/ZMM mapped to ARM64 equivalents. LZCNT is a bit_count instruction.
"""

neon_flag_model = """
LZCNT writes CF and ZF.
"""

neon_assembly = """
// NEON lowering: CLZ instruction on ARM64
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, and notes above are intentionally preserved as the source contract."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
