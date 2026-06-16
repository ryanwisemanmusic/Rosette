// CONDITIONAL/CMOVO.inc
// ARM64/NEON translation mirror generated from ISA/x86/CONDITIONAL/CMOVO.inc.
// Source contract: CMOVO — Move if overflow.

semantic = """
CMOVO: preserve the operation and form-specific semantic blocks.
Category: conditional_move.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONDITIONAL/CMOVO.inc"
x86_handler = "x86_cmovo"
neon_lowering = "arm64_cmovo"
lowering_kind = "arm64_conditional_move"

name = "CMOVO"
aliases = []
category = "conditional_move"
feature = "x86_gpr"
element_type = "u16_u32_u64"
element_size = 16

encodings = [
  { opcode = "0F 40 /r", form = "CMOVO r16, r/m16", op_en = "RM", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "0F 40 /r", form = "CMOVO r32, r/m32", op_en = "RM", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "REX.W + 0F 40 /r", form = "CMOVO r64, r/m64", op_en = "RM", feature = "x86_gpr_64", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  RM = ["ModRM:reg (r,w)", "ModRM:r/m (r)"]
}

lanes = { xmm = 0, ymm = 0 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "#GP if segment/limit violation",
  "#UD if LOCK prefix"
]

semantic_general = """
IF (OF=1)
    THEN DEST := SRC;
FI;
"""

handler = "x86_cmovo"
jit_lowering = "arm64_cmovo"
fallback = "zig_cmovo"

neon_register_model = """
x86 GPR mapped to ARM64 xN. CMOVO is a conditional scalar move.
"""

neon_flag_model = """
No x86 flags modified by CMOVO.
"""

neon_assembly = """
// NEON lowering: csel xDEST, xSRC, xDEST, vs
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
