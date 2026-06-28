// CONVERT/VCVTPS2PHX.inc
// ARM64/NEON translation mirror generated from ISA/x86/CONVERT/VCVTPS2PHX.inc.
// Source contract: VCVTPS2PHX — Convert Packed Single to Packed Half (FP16) with MXCSR rounding.

semantic = """
xmm1 := Convert_Packed_Single_To_Packed_Half(xmm2/m256/m32bcst)
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/VCVTPS2PHX.inc"
x86_handler = "x86_vcvtps2phx"
neon_lowering = "arm64_vcvtps2phx"
lowering_kind = "arm64_documented_contract"

name = "VCVTPS2PHX"
aliases = []
category = "avx512_fp16_convert"
feature = "avx512fp16"
element_type = "f16"
element_size = 16

encodings = [
  { opcode = "EVEX.128.66.MAP5.W0 1D /r", form = "VCVTPS2PHX xmm1{k1}{z}, xmm2/m128/m32bcst", op_en = "A", feature = "avx512fp16+avx512vl", vector_length = 128, encoding = "evex" }
  { opcode = "EVEX.256.66.MAP5.W0 1D /r", form = "VCVTPS2PHX ymm1{k1}{z}, ymm2/m256/m32bcst", op_en = "A", feature = "avx512fp16+avx512vl", vector_length = 256, encoding = "evex" }
  { opcode = "EVEX.512.66.MAP5.W0 1D /r", form = "VCVTPS2PHX zmm1{k1}{z}, zmm2/m512/m32bcst", op_en = "A", feature = "avx512fp16", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "ModRM:r/m (r)"]
}

lanes = { xmm = 4, ymm = 8 }
flags_written = []
simd_fp_exceptions = [
  "Invalid"
]
other_exceptions = [
  "#UD if EVEX prefix not present"
]

semantic_general = """
Convert packed single-precision FP32 values to packed half-precision FP16 values
using MXCSR rounding mode.
"""

handler = "x86_vcvtps2phx"
jit_lowering = "arm64_vcvtps2phx"
fallback = "zig_vcvtps2phx"

neon_register_model = """
x86 XMM/YMM/ZMM mapped to ARM64 Vn. VCVTPS2PHX is a AVX512-FP16 conversion.
"""

neon_flag_model = """
No x86 flags modified by VCVTPS2PHX.
"""

neon_assembly = """
// NEON lowering: VCVTPS2PHX conversion stub (avx512_fp16_convert)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
