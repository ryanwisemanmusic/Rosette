// COUNT/TZCNT.inc
// ARM64/NEON mirror generated from ISA/x86/COUNT/TZCNT.inc.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "COUNT/TZCNT.inc"
x86_handler = "x86_tzcnt"
neon_lowering = "arm64_tzcnt"
lowering_kind = "arm64_documented_contract"

name = "TZCNT"
aliases = []
category = "bit_count"
feature = "BMI1"
element_type = "u16_u32_u64"
element_size = 16

encodings = [
  { opcode = "F3 0F BC /r", form = "TZCNT r16, r/m16", op_en = "RM", feature = "BMI1", vector_length = 0, encoding = "legacy" },
  { opcode = "F3 0F BC /r", form = "TZCNT r32, r/m32", op_en = "RM", feature = "BMI1", vector_length = 0, encoding = "legacy" },
  { opcode = "F3 REX.W 0F BC /r", form = "TZCNT r64, r/m64", op_en = "RM", feature = "BMI1", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  RM = ["ModRM:reg (w)", "ModRM:r/m (r)"]
}

flags_written = ["CF", "ZF"]
simd_fp_exceptions = []

semantic_general = """
Count the number of trailing zero bits in the source operand and store the result in the destination.
"""

handler = "x86_tzcnt"
jit_lowering = "arm64_tzcnt"
fallback = "zig_tzcnt"

neon_register_model = """
TZCNT is a bit_count instruction. ARM64 CLZ/RBIT available.
"""

neon_flag_model = """
TZCNT writes CF and ZF.
"""

neon_assembly = """
// NEON lowering: RBIT + CLZ instruction sequence on ARM64
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
