// CONVERT/CVTSS2SD.inc
// ARM64/NEON translation mirror generated from ISA/x86/CONVERT/CVTSS2SD.inc.
// Source contract: CVTSS2SD — Packed/Scalar Convert.

semantic = """
CVTSS2SD: preserve the operation and form-specific semantic blocks.
Category: sse2_convert.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/CVTSS2SD.inc"
x86_handler = "x86_cvtss2sd"
neon_lowering = "arm64_cvtss2sd"
lowering_kind = "arm64_documented_contract"

name = "CVTSS2SD"
aliases = []
category = "sse2_convert"
feature = "SSE2_AVX_AVX512F"
element_type = "f64"
element_size = 64

encodings = [
  { opcode = "F3 0F 5A /r", form = "CVTSS2SD xmm1, xmm2/m32", op_en = "A", feature = "SSE2", vector_length = 0, encoding = "legacy_sse" },
  { opcode = "VEX.LIG.F3.0F.W0 0F 5A /r", form = "VCVTSS2SD xmm1, xmm2, xmm3/m32{sae}", op_en = "B", feature = "AVX", vector_length = 0, encoding = "vex" },
  { opcode = "EVEX.LIG.F3.0F.W0 0F 5A /r", form = "VCVTSS2SD xmm1{k1}{z}, xmm2, xmm3/m32{sae}", op_en = "C", feature = "AVX512F", vector_length = 0, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "ModRM:r/m (r)"],
  B = ["ModRM:reg (w)", "VEX.vvvv (r)", "ModRM:r/m (r)"],
  C = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)"]
}

lanes = { xmm = 0, ymm = 0 }
flags_written = []
simd_fp_exceptions = ["precision", "inexact"]
other_exceptions = [
  "Non-EVEX encoded instruction uses Type 1 class exception conditions",
  "EVEX encoded instruction uses Type E1 class exception conditions"
]

handler = "x86_cvtss2sd"
jit_lowering = "arm64_cvtss2sd"
fallback = "zig_cvtss2sd"

neon_register_model = """
x86 xmm/ymm scalar lanes are mapped into ARM64 SIMD scalar registers. CVTSS2SD is a scalar conversion between floating-point and integer formats.
"""

neon_flag_model = """
No x86 flags are modified by CVTSS2SD.
"""

neon_assembly = """
// NEON lowering: scalar fcvt / fcvtzu / scvtf
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
