// CONVERT/CVTTPD2PI.inc
// ARM64/NEON translation mirror generated from ISA/x86/CONVERT/CVTTPD2PI.inc.
// Source contract: CVTTPD2PI — Packed/Scalar Convert.

semantic = """
CVTTPD2PI: preserve the operation and form-specific semantic blocks.
Category: mmx_convert.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/CVTTPD2PI.inc"
x86_handler = "x86_cvttpd2pi"
neon_lowering = "arm64_cvttpd2pi"
lowering_kind = "arm64_documented_contract"

name = "CVTTPD2PI"
aliases = []
category = "mmx_convert"
feature = "SSE2_MMX"
element_type = "i32"
element_size = 64

encodings = [
  { opcode = "66 0F 2C /r", form = "CVTTPD2PI mm1, xmm2/m128", op_en = "A", feature = "SSE2", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  A = ["ModRM:reg (r,w)", "ModRM:r/m (r)"],
}

lanes = { xmm = 0, ymm = 0 }
flags_written = []
simd_fp_exceptions = ["invalid", "inexact"]
other_exceptions = [
  "Non-EVEX encoded instruction uses Type 1 class exception conditions",
  "EVEX encoded instruction uses Type E1 class exception conditions"
]

handler = "x86_cvttpd2pi"
jit_lowering = "arm64_cvttpd2pi"
fallback = "zig_cvttpd2pi"

neon_register_model = """
x86 MMX registers are mapped into ARM64 general-purpose or SIMD registers. CVTTPD2PI is an MMX+SSE conversion.
"""

neon_flag_model = """
No x86 flags are modified by CVTTPD2PI.
"""

neon_assembly = """
// NEON lowering: documented contract; platform-optimized sequence
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
