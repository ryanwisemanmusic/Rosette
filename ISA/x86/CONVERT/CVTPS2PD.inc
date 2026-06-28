// CONVERT/CVTPS2PD.inc
// ARM64/NEON translation mirror generated from ISA/x86/CONVERT/CVTPS2PD.inc.
// Source contract: CVTPS2PD — Packed/Scalar Convert.

semantic = """
CVTPS2PD: preserve the operation and form-specific semantic blocks.
Category: sse2_convert.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/CVTPS2PD.inc"
x86_handler = "x86_cvtps2pd"
neon_lowering = "arm64_cvtps2pd"
lowering_kind = "neon_vector"

name = "CVTPS2PD"
aliases = []
category = "sse2_convert"
feature = "SSE2_AVX_AVX512F"
element_type = "f64"
element_size = 64

encodings = [
  { opcode = "NP 0F 5A /r", form = "CVTPS2PD xmm1, m64", op_en = "A", feature = "SSE2", vector_length = 128, encoding = "legacy_sse" },
  { opcode = "VEX.128.0F 0F 5A /r", form = "VCVTPS2PD xmm1, xmm2, m64", op_en = "B", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.0F 0F 5A /r", form = "VCVTPS2PD ymm1, ymm2, xmm3/m128", op_en = "B", feature = "AVX", vector_length = 256, encoding = "vex" },
  { opcode = "EVEX.128.0F.W0 0F 5A /r", form = "VCVTPS2PD xmm1{k1}{z}, xmm2, xmm3/m64/m64bcst", op_en = "C", feature = "AVX512VL+AVX512F", vector_length = 128, encoding = "evex", broadcast = "m64bcst" },
  { opcode = "EVEX.256.0F.W0 0F 5A /r", form = "VCVTPS2PD ymm1{k1}{z}, ymm2, ymm3/m128/m64bcst", op_en = "C", feature = "AVX512VL+AVX512F", vector_length = 256, encoding = "evex", broadcast = "m64bcst" },
  { opcode = "EVEX.512.0F.W0 0F 5A /r", form = "VCVTPS2PD zmm1{k1}{z}, zmm2, zmm3/m256/m64bcst", op_en = "C", feature = "AVX512F", vector_length = 512, encoding = "evex", broadcast = "m64bcst" }
]

operand_encoding = {
  A = ["ModRM:reg (r,w)", "ModRM:r/m (r)"],
  B = ["ModRM:reg (w)", "VEX.vvvv (r)", "ModRM:r/m (r)"],
  C = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)"]
}

lanes = { xmm = 2, ymm = 4, zmm = 8 }
flags_written = []
simd_fp_exceptions = ["precision", "inexact"]
other_exceptions = [
  "Non-EVEX encoded instruction uses Type 1 class exception conditions",
  "EVEX encoded instruction uses Type E1 class exception conditions"
]

handler = "x86_cvtps2pd"
jit_lowering = "arm64_cvtps2pd"
fallback = "zig_cvtps2pd"

neon_register_model = """
x86 xmm/ymm/zmm lanes are mapped into ARM64 vector registers. CVTPS2PD is a packed conversion between floating-point and integer formats.
"""

neon_flag_model = """
No x86 flags are modified by CVTPS2PD.
"""

neon_assembly = """
// NEON lowering: vector fcvt / fcvtzu / scvtf
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
