// CONDITIONAL/CMOVA.inc
// ARM64/NEON translation mirror generated from ISA/x86/CONDITIONAL/CMOVA.inc.
// Source contract: CMOVA — Move if above.

semantic = """
CMOVA: preserve the operation and form-specific semantic blocks.
Category: conditional_move.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONDITIONAL/CMOVA.inc"
x86_handler = "x86_cmova"
neon_lowering = "arm64_cmova"
lowering_kind = "arm64_conditional_move"

name = "CMOVA"
aliases = []
category = "conditional_move"
feature = "x86_gpr"
element_type = "u16_u32_u64"
element_size = 16

encodings = [
  { opcode = "0F 47 /r", form = "CMOVA r16, r/m16", op_en = "RM", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "0F 47 /r", form = "CMOVA r32, r/m32", op_en = "RM", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "REX.W + 0F 47 /r", form = "CMOVA r64, r/m64", op_en = "RM", feature = "x86_gpr_64", vector_length = 0, encoding = "legacy" }
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
IF (CF=0 AND ZF=0)
    THEN DEST := SRC;
FI;
"""

handler = "x86_cmova"
jit_lowering = "arm64_cmova"
fallback = "zig_cmova"

neon_register_model = """
x86 GPR mapped to ARM64 xN. CMOVA is a conditional scalar move.
"""

neon_flag_model = """
No x86 flags modified by CMOVA.
"""

neon_assembly = """
// NEON lowering: csel xDEST, xSRC, xDEST, hi
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
