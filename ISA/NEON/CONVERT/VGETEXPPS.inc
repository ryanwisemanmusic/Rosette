// CONVERT/VGETEXPPS.inc
// ARM64/NEON mirror generated from ISA/x86/CONVERT/VGETEXPPS.inc.
// This file preserves the x86 source contract and supplies the ARM64 lowering contract.

semantic = """
VGETEXPPS: preserve the operation and form-specific semantic blocks.
Category: avx512_convert.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/VGETEXPPS.inc"
x86_handler = "x86_vgetexpps"
neon_lowering = "arm64_vgetexpps"
lowering_kind = "arm64_documented_contract"

name = "VGETEXPPS"
aliases = []
category = "avx512_convert"
feature = "avx512f"
element_type = "f32"
element_size = 32

encodings = [
  { opcode = "EVEX.128.66.0F38.W0 42 /r", form = "VGETEXPPS xmm1{k1}{z}, xmm2/m128/m32bcst", op_en = "A", feature = "avx512f+avx512vl", vector_length = 128, encoding = "evex", broadcast = "m32bcst" },
  { opcode = "EVEX.256.66.0F38.W0 42 /r", form = "VGETEXPPS ymm1{k1}{z}, ymm2/m256/m32bcst", op_en = "A", feature = "avx512f+avx512vl", vector_length = 256, encoding = "evex", broadcast = "m32bcst" },
  { opcode = "EVEX.512.66.0F38.W0 42 /r", form = "VGETEXPPS zmm1{k1}{z}, zmm2/m512/m32bcst", op_en = "A", feature = "avx512f", vector_length = 512, encoding = "evex", broadcast = "m32bcst" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "ModRM:r/m (r)"]
}

lanes = { xmm = 4, ymm = 8, zmm = 16 }
flags_written = []
simd_fp_exceptions = ["Invalid", "Inexact", "Overflow", "Underflow"]
other_exceptions = [
  "#UD if LOCK prefix",
  "#UD if EVEX.Z = 1 and no masking mode"
]

semantic_general = """
Extract exponent of packed single-precision floating-point values as FP32.
The exponent is extracted as a biased FP32 value for each lane.
"""

handler = "x86_vgetexpps"
jit_lowering = "arm64_vgetexpps"
fallback = "zig_vgetexpps"

neon_register_model = """
x86 XMM/YMM/ZMM mapped to ARM64 Vn. VGETEXPPS is an AVX512 extract-exponent conversion.
"""

neon_flag_model = """
No x86 flags modified by VGETEXPPS.
"""

neon_assembly = """
// NEON lowering: VGETEXPPS conversion stub (avx512_convert)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
