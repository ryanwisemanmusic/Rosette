// CONDITIONAL/FCMOVBE.inc
// ARM64/NEON translation mirror generated from ISA/x86/CONDITIONAL/FCMOVBE.inc.
// Source contract: FCMOVBE — FP Conditional Move if below or equal.

semantic = """
FCMOVBE: preserve the operation and form-specific semantic blocks.
Category: x87_fpu.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONDITIONAL/FCMOVBE.inc"
x86_handler = "x86_fcmovbe"
neon_lowering = "arm64_fcmovbe"
lowering_kind = "arm64_conditional_move"

name = "FCMOVBE"
aliases = []
category = "x87_fpu"
feature = "x87_fpu"
element_type = "f80"
element_size = 80

encodings = [
  { opcode = "DA D0+i", form = "FCMOVBE ST(0), ST(i)", op_en = "REG", feature = "x87_fpu", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  REG = ["ST(0) (r,w)", "ST(i) (r)"]
}

lanes = { xmm = 0, ymm = 0 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "#NM if CR0.EM or CR0.TS",
  "#UD if LOCK prefix"
]

semantic_general = """
IF (CF=1 OR ZF=1)
    THEN ST(0) := ST(i);
FI;
"""

handler = "x86_fcmovbe"
jit_lowering = "arm64_fcmovbe"
fallback = "zig_fcmovbe"

neon_register_model = """
x87 FP stack mapped to ARM64 register file via soft-float emulation.
"""

neon_flag_model = """
x87 FP status flags mapped to ARM64 NZCV.
"""

neon_assembly = """
// NEON lowering: soft-float conditional move based on emulated x87 condition flags.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
