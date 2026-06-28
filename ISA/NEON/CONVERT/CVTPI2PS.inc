// CONVERT/CVTPI2PS.inc
// ARM64/NEON translation mirror generated from ISA/x86/CONVERT/CVTPI2PS.inc.
// Source contract: CVTPI2PS — Packed/Scalar Convert.

semantic = """
CVTPI2PS: preserve the operation and form-specific semantic blocks.
Category: mmx_convert.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/CVTPI2PS.inc"
x86_handler = "x86_cvtpi2ps"
neon_lowering = "arm64_cvtpi2ps"
lowering_kind = "arm64_documented_contract"

name = "CVTPI2PS"
aliases = []
category = "mmx_convert"
feature = "SSE_MMX"
element_type = "f32"
element_size = 32

encodings = [
  { opcode = "NP 0F 2A /r", form = "CVTPI2PS xmm1, mm2/m64", op_en = "A", feature = "SSE", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  A = ["ModRM:reg (r,w)", "ModRM:r/m (r)"],
}

lanes = { xmm = 0, ymm = 0 }
flags_written = []
simd_fp_exceptions = ["precision", "inexact"]
other_exceptions = [
  "Non-EVEX encoded instruction uses Type 1 class exception conditions",
  "EVEX encoded instruction uses Type E1 class exception conditions"
]

handler = "x86_cvtpi2ps"
jit_lowering = "arm64_cvtpi2ps"
fallback = "zig_cvtpi2ps"

neon_register_model = """
x86 MMX registers are mapped into ARM64 general-purpose or SIMD registers. CVTPI2PS is an MMX+SSE conversion.
"""

neon_flag_model = """
No x86 flags are modified by CVTPI2PS.
"""

neon_assembly = """
// NEON lowering: documented contract; platform-optimized sequence
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
