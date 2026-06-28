// NEON/CONVERT/VCVTQQ2PH.inc
// ARM64/NEON mirror generated from ISA/x86/CONVERT/VCVTQQ2PH.inc.

semantic = """
VCVTQQ2PH: preserve the operation and form-specific semantic blocks.
Category: avx512_fp16_convert.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/VCVTQQ2PH.inc"
x86_handler = "x86_vcvtqq2ph"
neon_lowering = "arm64_vcvtqq2ph"
lowering_kind = "arm64_documented_contract"

name = "VCVTQQ2PH"
aliases = []
category = "avx512_fp16_convert"
feature = "avx512fp16"
element_type = "f16"
element_size = 16

encodings = [
  { opcode = "EVEX.128.NP.MAP5.W1 5B /r", form = "VCVTQQ2PH xmm1{k1}{z}, xmm2/m128/m64bcst", op_en = "A", feature = "avx512fp16", vector_length = 0, encoding = "legacy" }
  { opcode = "EVEX.256.NP.MAP5.W1 5B /r", form = "VCVTQQ2PH xmm1{k1}{z}, ymm2/m256/m64bcst", op_en = "A", feature = "avx512fp16", vector_length = 0, encoding = "legacy" }
  { opcode = "EVEX.512.NP.MAP5.W1 5B /r", form = "VCVTQQ2PH ymm1{k1}{z}, zmm2/m512/m64bcst", op_en = "A", feature = "avx512fp16", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "ModRM:r/m (r)"]
}

lanes = { xmm = 2, ymm = 4 }
flags_written = []
simd_fp_exceptions = [
  "Invalid"
]
other_exceptions = [
  "#UD if EVEX prefix not present"
]

semantic_general = """
Convert packed quadword integers to packed half-precision FP16 values.
"""

handler = "x86_vcvtqq2ph"
jit_lowering = "arm64_vcvtqq2ph"
fallback = "zig_vcvtqq2ph"

neon_register_model = """
x86 XMM/YMM/ZMM mapped to ARM64 Vn. VCVTQQ2PH is a AVX512-FP16 conversion.
"""

neon_flag_model = """
No x86 flags modified by VCVTQQ2PH.
"""

neon_assembly = """
// NEON lowering: VCVTQQ2PH conversion stub (avx512_fp16_convert)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
