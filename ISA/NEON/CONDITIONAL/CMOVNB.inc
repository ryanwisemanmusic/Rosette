// NEON/CONDITIONAL/CMOVNB.inc
// ARM64/NEON mirror generated from ISA/x86/CONDITIONAL/CMOVNB.inc.

semantic = """
CMOVNB: preserve the operation and form-specific semantic blocks.
Category: conditional_move.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONDITIONAL/CMOVNB.inc"
x86_handler = "x86_cmovnb"
neon_lowering = "arm64_cmovnb"
lowering_kind = "arm64_conditional_move"

name = "CMOVNB"
aliases = []
category = "conditional_move"
feature = "x86_gpr"
element_type = "u16_u32_u64"
element_size = 16

encodings = [
  { opcode = "0F 43 /r", form = "CMOVNB r16, r/m16", op_en = "RM", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "0F 43 /r", form = "CMOVNB r32, r/m32", op_en = "RM", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "REX.W + 0F 43 /r", form = "CMOVNB r64, r/m64", op_en = "RM", feature = "x86_gpr", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  RM = ["ModRM:reg (r,w)", "ModRM:r/m (r)"]
}

lanes = { xmm = 0, ymm = 0 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "#UD if LOCK prefix"
]

semantic_general = """
Move if not below (CF=0).
"""

handler = "x86_cmovnb"
jit_lowering = "arm64_cmovnb"
fallback = "zig_cmovnb"

neon_register_model = """
x86 GPR mapped to ARM64 xN. CMOVcc is a conditional move using ARM64 csel.
"""

neon_flag_model = """
No x86 flags modified by CMOVcc.
"""

neon_assembly = """
// NEON lowering: csel xDEST, xSRC, xZERO, COND
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
