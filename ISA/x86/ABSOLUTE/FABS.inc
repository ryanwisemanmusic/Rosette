// ABSOLUTE/FABS.inc
// ARM64/NEON translation mirror generated from ISA/x86/ABSOLUTE/FABS.inc.
// Source contract: FABS — Absolute Value.

semantic = """
ST(0) := |ST(0)|
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ABSOLUTE/FABS.inc"
x86_handler = "x86_fabs"
neon_lowering = "arm64_fabs"
lowering_kind = "arm64_scalar"

name = "FABS"
aliases = []
category = "floating_point_absolute"
feature = "x87_fpu"
element_type = "f80"

encodings = [
  { opcode = "D9 E1", form = "FABS", op_en = "ZO", feature = "x87_FPU", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = ["N/A"]
}

lanes = { xmm = 0, ymm = 0 }
flags_written = ["C1"]
simd_fp_exceptions = []
other_exceptions = [
  "#IS if stack underflow",
  "#NM if CR0.EM or CR0.TS = 1",
  "#UD if LOCK prefix"
]

semantic_general = """
ST(0) := |ST(0)|;
"""

handler = "x86_fabs"
jit_lowering = "arm64_fabs"
fallback = "zig_fabs"

neon_register_model = """
x87 FPU stack mapped to ARM64 vN registers. FABS is a scalar absolute-value operation on the x87 top-of-stack.
"""

neon_flag_model = """
ARM64 FABS does not update flags. x87 C1 flag needs separate tracking if required.
"""

neon_assembly = """
// NEON lowering: fabs dDEST, dSRC
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
