// NEON/CONVERT/VCVTQQ2PS.inc
// ARM64/NEON mirror generated from ISA/x86/CONVERT/VCVTQQ2PS.inc.

semantic = """
VCVTQQ2PS: preserve the operation and form-specific semantic blocks.
Category: avx512_convert.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/VCVTQQ2PS.inc"
x86_handler = "x86_vcvtqq2ps"
neon_lowering = "arm64_vcvtqq2ps"
lowering_kind = "arm64_documented_contract"

name = "VCVTQQ2PS"
aliases = []
category = "avx512_convert"
feature = "avx512f"
element_type = "f32"
element_size = 32

encodings = [
  { opcode = "EVEX.128.0F.W1 5B /r", form = "VCVTQQ2PS xmm1{k1}{z}, xmm2/m128/m64bcst", op_en = "A", feature = "avx512f", vector_length = 0, encoding = "legacy" }
  { opcode = "EVEX.256.0F.W1 5B /r", form = "VCVTQQ2PS xmm1{k1}{z}, ymm2/m256/m64bcst", op_en = "A", feature = "avx512f", vector_length = 0, encoding = "legacy" }
  { opcode = "EVEX.512.0F.W1 5B /r", form = "VCVTQQ2PS ymm1{k1}{z}, zmm2/m512/m64bcst", op_en = "A", feature = "avx512f", vector_length = 0, encoding = "legacy" }
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
Convert packed quadword integers to packed single-precision FP32 values.
"""

handler = "x86_vcvtqq2ps"
jit_lowering = "arm64_vcvtqq2ps"
fallback = "zig_vcvtqq2ps"

neon_register_model = """
x86 XMM/YMM/ZMM mapped to ARM64 Vn. VCVTQQ2PS is a AVX512 conversion.
"""

neon_flag_model = """
No x86 flags modified by VCVTQQ2PS.
"""

neon_assembly = """
// NEON lowering: VCVTQQ2PS conversion stub (avx512_convert)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
