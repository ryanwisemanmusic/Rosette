// NEON/CONDITIONAL/FCMOVE.inc
// ARM64/NEON mirror generated from ISA/x86/CONDITIONAL/FCMOVE.inc.

semantic = """
FCMOVE: preserve the operation and form-specific semantic blocks.
Category: x87_fpu.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONDITIONAL/FCMOVE.inc"
x86_handler = "x86_fcmove"
neon_lowering = "arm64_fcmove"
lowering_kind = "arm64_fpu_conditional_move"

name = "FCMOVE"
aliases = []
category = "x87_fpu"
feature = "x87_fpu"
element_type = "f80"
element_size = 80

encodings = [
  { opcode = "DA C8+i", form = "FCMOVE ST(0), ST(i)", op_en = "REG", feature = "x87_fpu", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  REG = ["ST(0) (r,w)", "ST(i) (r)"]
}

lanes = { xmm = 0, ymm = 0 }
flags_written = ["C1"]
simd_fp_exceptions = []
other_exceptions = [
  "#NM if CR0.EM or CR0.TS = 1",
  "#UD if LOCK prefix"
]

semantic_general = """
Move if equal (ZF=1).
"""

handler = "x86_fcmove"
jit_lowering = "arm64_fcmove"
fallback = "zig_fcmove"

neon_register_model = """
x87 FPU register stack mapped to ARM64 dN registers. FCMOVcc is a conditional move on ARM64 using fcsel.
"""

neon_flag_model = """
C1 set to 0 if stack underflow occurred. C0, C2, C3 undefined.
"""

neon_assembly = """
// NEON lowering: fcsel dDEST, dSRC, dZERO, COND
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
