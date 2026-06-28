// CONVERT/VCVTPS2PH.inc
// ARM64/NEON translation mirror generated from ISA/x86/CONVERT/VCVTPS2PH.inc.
// Source contract: VCVTPS2PH — Convert Packed Single to Packed Half (FP16).

semantic = """
xmm1/m64 := Convert_Packed_Single_To_Packed_Half(xmm2, imm8)
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/VCVTPS2PH.inc"
x86_handler = "x86_vcvtps2ph"
neon_lowering = "arm64_vcvtps2ph"
lowering_kind = "arm64_documented_contract"

name = "VCVTPS2PH"
aliases = []
category = "avx_fp16_convert"
feature = "f16c"
element_type = "f16"
element_size = 16

encodings = [
  { opcode = "VEX.128.66.0F3A.W0 1D /r ib", form = "VCVTPS2PH xmm1/m64, xmm2, imm8", op_en = "A", feature = "f16c", vector_length = 128, encoding = "vex" }
  { opcode = "VEX.256.66.0F3A.W0 1D /r ib", form = "VCVTPS2PH xmm1/m128, ymm2, imm8", op_en = "A", feature = "f16c", vector_length = 256, encoding = "vex" }
  { opcode = "EVEX.128.66.0F3A.W0 1D /r ib", form = "VCVTPS2PH xmm1{k1}{z}, xmm2/m128/m32bcst, imm8", op_en = "A", feature = "avx512fp16+avx512vl", vector_length = 128, encoding = "evex" }
  { opcode = "EVEX.256.66.0F3A.W0 1D /r ib", form = "VCVTPS2PH xmm1{k1}{z}, ymm2/m256/m32bcst, imm8", op_en = "A", feature = "avx512fp16+avx512vl", vector_length = 256, encoding = "evex" }
  { opcode = "EVEX.512.66.0F3A.W0 1D /r ib", form = "VCVTPS2PH ymm1{k1}{z}, zmm2/m512/m32bcst, imm8", op_en = "A", feature = "avx512fp16", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:r/m (w)", "ModRM:reg (r)"]
}

lanes = { xmm = 4, ymm = 8 }
flags_written = []
simd_fp_exceptions = [
  "Invalid"
]
other_exceptions = [
  "#UD if VEX or EVEX prefix not present"
]

semantic_general = """
Convert packed single-precision FP32 values to packed half-precision FP16 values;
rounding control specified via imm8[1:0].
"""

handler = "x86_vcvtps2ph"
jit_lowering = "arm64_vcvtps2ph"
fallback = "zig_vcvtps2ph"

neon_register_model = """
x86 XMM/YMM/ZMM mapped to ARM64 Vn. VCVTPS2PH is a FP16 conversion.
"""

neon_flag_model = """
No x86 flags modified by VCVTPS2PH.
"""

neon_assembly = """
// NEON lowering: VCVTPS2PH conversion stub (avx_fp16_convert)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
