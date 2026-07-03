// CONVERT/VGETEXPPH.inc
// ARM64/NEON mirror generated from ISA/x86/CONVERT/VGETEXPPH.inc.
// This file preserves the x86 source contract and supplies the ARM64 lowering contract.

semantic = """
VGETEXPPH: preserve the operation and form-specific semantic blocks.
Category: avx512_fp16_convert.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/VGETEXPPH.inc"
x86_handler = "x86_vgetexpph"
neon_lowering = "arm64_vgetexpph"
lowering_kind = "arm64_documented_contract"

name = "VGETEXPPH"
aliases = []
category = "avx512_fp16_convert"
feature = "avx512fp16"
element_type = "f16"
element_size = 16

encodings = [
  { opcode = "EVEX.128.66.MAP5.W0 42 /r", form = "VGETEXPPH xmm1{k1}{z}, xmm2/m128/m16bcst", op_en = "A", feature = "avx512fp16+avx512vl", vector_length = 128, encoding = "evex", broadcast = "m16bcst" },
  { opcode = "EVEX.256.66.MAP5.W0 42 /r", form = "VGETEXPPH ymm1{k1}{z}, ymm2/m256/m16bcst", op_en = "A", feature = "avx512fp16+avx512vl", vector_length = 256, encoding = "evex", broadcast = "m16bcst" },
  { opcode = "EVEX.512.66.MAP5.W0 42 /r", form = "VGETEXPPH zmm1{k1}{z}, zmm2/m512/m16bcst", op_en = "A", feature = "avx512fp16", vector_length = 512, encoding = "evex", broadcast = "m16bcst" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "ModRM:r/m (r)"]
}

lanes = { xmm = 8, ymm = 16, zmm = 32 }
flags_written = []
simd_fp_exceptions = ["Invalid", "Inexact", "Overflow", "Underflow"]
other_exceptions = [
  "#UD if LOCK prefix",
  "#UD if EVEX.Z = 1 and no masking mode"
]

semantic_general = """
Extract exponent of packed half-precision floating-point values as FP16.
The exponent is extracted as a biased FP16 value for each lane.
"""

handler = "x86_vgetexpph"
jit_lowering = "arm64_vgetexpph"
fallback = "zig_vgetexpph"

neon_register_model = """
x86 XMM/YMM/ZMM mapped to ARM64 Vn. VGETEXPPH is an AVX512-FP16 extract-exponent conversion.
"""

neon_flag_model = """
No x86 flags modified by VGETEXPPH.
"""

neon_assembly = """
// NEON lowering: VGETEXPPH conversion stub (avx512_fp16_convert)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
