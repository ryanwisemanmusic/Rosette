// SCALE/FSCALE.inc
// ARM64/NEON translation mirror generated from ISA/x86/SCALE/FSCALE.inc.
// Source contract: FSCALE — Scale.

semantic = """
ST(0) := ST(0) * 2^ST(1);
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SCALE/FSCALE.inc"
x86_handler = "x86_fscale"
neon_lowering = "arm64_fscale"
lowering_kind = "arm64_documented_contract"

name = "FSCALE"
aliases = []
category = "x87_fpu"
feature = "x87_fpu"
element_type = "f80"

encodings = [
  { opcode = "D9 FD", form = "FSCALE", op_en = "ZO", feature = "x87_FPU", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = ["N/A"]
}

lanes = { xmm = 0, ymm = 0 }
flags_written = ["c1"]
simd_fp_exceptions = []
other_exceptions = [
  "#IS if stack underflow",
  "#IA if overflow/underflow with unmasked precision exception",
  "#D if source operand is denormal",
  "#U if result underflows",
  "#O if result overflows",
  "#P if precision exception",
  "#NM if CR0.EM or CR0.TS = 1",
  "#UD if LOCK prefix"
]

semantic_general = """
ST(0) := ST(0) * 2^ST(1);
"""

handler = "x86_fscale"
jit_lowering = "arm64_fscale"
fallback = "zig_fscale"

neon_register_model = """
x87 FPU stack mapped to ARM64 vN registers. FSCALE is a scalar scale operation on the x87 top-of-stack.
"""

neon_flag_model = """
ARM64 FSCALE does not update flags. x87 C1 flag needs separate tracking if required.
"""

neon_assembly = """
// NEON lowering: fscale dDEST, dDEST, dSRC
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
