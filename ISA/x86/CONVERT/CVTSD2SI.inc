// CONVERT/CVTSD2SI.inc
// ARM64/NEON translation mirror generated from ISA/x86/CONVERT/CVTSD2SI.inc.
// Source contract: CVTSD2SI — Packed/Scalar Convert.

semantic = """
CVTSD2SI: preserve the operation and form-specific semantic blocks.
Category: sse2_convert.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/CVTSD2SI.inc"
x86_handler = "x86_cvtsd2si"
neon_lowering = "arm64_cvtsd2si"
lowering_kind = "neon_scalar"

name = "CVTSD2SI"
aliases = []
category = "sse2_convert"
feature = "SSE2_AVX_AVX512F"
element_type = "i32"
element_size = 32

encodings = [
  { opcode = "F2 0F 2D /r", form = "CVTSD2SI r32, xmm2/m64", op_en = "A", feature = "SSE2", vector_length = 0, encoding = "legacy_sse" },
  { opcode = "F2 REX.W 0F 2D /r", form = "CVTSD2SI r64, xmm2/m64", op_en = "A", feature = "SSE2", vector_length = 0, encoding = "legacy_sse" },
  { opcode = "VEX.LIG.F2.0F.W0 0F 2D /r", form = "VCVTSD2SI r32, xmm1, xmm2/m64", op_en = "A", feature = "AVX", vector_length = 0, encoding = "vex" },
  { opcode = "VEX.LIG.F2.0F.W1 0F 2D /r", form = "VCVTSD2SI r64, xmm1, xmm2/m64", op_en = "A", feature = "AVX", vector_length = 0, encoding = "vex" },
  { opcode = "EVEX.LIG.F2.0F.W0 0F 2D /r", form = "VCVTSD2SI r32{k1}{z}, xmm1, xmm2/m64{er}", op_en = "A", feature = "AVX512F", vector_length = 0, encoding = "evex" },
  { opcode = "EVEX.LIG.F2.0F.W1 0F 2D /r", form = "VCVTSD2SI r64{k1}{z}, xmm1, xmm2/m64{er}", op_en = "A", feature = "AVX512F", vector_length = 0, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "ModRM:r/m (r)"],
  B = ["ModRM:reg (w)", "VEX.vvvv (r)", "ModRM:r/m (r)"],
  C = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)"]
}

lanes = { xmm = 0, ymm = 0 }
flags_written = []
simd_fp_exceptions = ["invalid", "inexact"]
other_exceptions = [
  "Non-EVEX encoded instruction uses Type 1 class exception conditions",
  "EVEX encoded instruction uses Type E1 class exception conditions"
]

handler = "x86_cvtsd2si"
jit_lowering = "arm64_cvtsd2si"
fallback = "zig_cvtsd2si"

neon_register_model = """
x86 xmm/ymm scalar lanes are mapped into ARM64 SIMD scalar registers. CVTSD2SI is a scalar conversion between floating-point and integer formats.
"""

neon_flag_model = """
No x86 flags are modified by CVTSD2SI.
"""

neon_assembly = """
// NEON lowering: scalar fcvt / fcvtzu / scvtf
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
