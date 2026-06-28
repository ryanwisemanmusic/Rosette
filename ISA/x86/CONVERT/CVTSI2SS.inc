// CONVERT/CVTSI2SS.inc
// ARM64/NEON translation mirror generated from ISA/x86/CONVERT/CVTSI2SS.inc.
// Source contract: CVTSI2SS — Packed/Scalar Convert.

semantic = """
CVTSI2SS: preserve the operation and form-specific semantic blocks.
Category: sse_convert.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/CVTSI2SS.inc"
x86_handler = "x86_cvtsi2ss"
neon_lowering = "arm64_cvtsi2ss"
lowering_kind = "neon_scalar"

name = "CVTSI2SS"
aliases = []
category = "sse_convert"
feature = "SSE_AVX_AVX512F"
element_type = "f32"
element_size = 32

encodings = [
  { opcode = "F3 0F 2A /r", form = "CVTSI2SS xmm1, r/m32", op_en = "A", feature = "SSE", vector_length = 0, encoding = "legacy_sse" },
  { opcode = "F3 REX.W 0F 2A /r", form = "CVTSI2SS xmm1, r/m64", op_en = "A", feature = "SSE", vector_length = 0, encoding = "legacy_sse" },
  { opcode = "VEX.LIG.F3.0F.W0 0F 2A /r", form = "VCVTSI2SS xmm1, xmm2, r/m32", op_en = "B", feature = "AVX", vector_length = 0, encoding = "vex" },
  { opcode = "VEX.LIG.F3.0F.W1 0F 2A /r", form = "VCVTSI2SS xmm1, xmm2, r/m64", op_en = "B", feature = "AVX", vector_length = 0, encoding = "vex" },
  { opcode = "EVEX.LIG.F3.0F.W0 0F 2A /r", form = "VCVTSI2SS xmm1{k1}{z}, xmm2, r/m32{er}", op_en = "C", feature = "AVX512F", vector_length = 0, encoding = "evex" },
  { opcode = "EVEX.LIG.F3.0F.W1 0F 2A /r", form = "VCVTSI2SS xmm1{k1}{z}, xmm2, r/m64{er}", op_en = "C", feature = "AVX512F", vector_length = 0, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (r,w)", "ModRM:r/m (r)"],
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

handler = "x86_cvtsi2ss"
jit_lowering = "arm64_cvtsi2ss"
fallback = "zig_cvtsi2ss"

neon_register_model = """
x86 xmm/ymm scalar lanes are mapped into ARM64 SIMD scalar registers. CVTSI2SS is a scalar conversion between floating-point and integer formats.
"""

neon_flag_model = """
No x86 flags are modified by CVTSI2SS.
"""

neon_assembly = """
// NEON lowering: scalar fcvt / fcvtzu / scvtf
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
