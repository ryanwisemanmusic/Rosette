// CONVERT/VCVTPS2UDQ.inc
// ARM64/NEON translation mirror generated from ISA/x86/CONVERT/VCVTPS2UDQ.inc.
// Source contract: VCVTPS2UDQ — Convert Packed Single to Packed Unsigned Dword.

semantic = """
xmm1 := Convert_Packed_Single_To_Packed_Unsigned_Dword(xmm2/m128/m32bcst)
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/VCVTPS2UDQ.inc"
x86_handler = "x86_vcvtps2udq"
neon_lowering = "arm64_vcvtps2udq"
lowering_kind = "arm64_documented_contract"

name = "VCVTPS2UDQ"
aliases = []
category = "avx512_convert"
feature = "avx512f"
element_type = "u32"
element_size = 32

encodings = [
  { opcode = "EVEX.128.0F.W0 79 /r", form = "VCVTPS2UDQ xmm1{k1}{z}, xmm2/m128/m32bcst", op_en = "A", feature = "avx512vl+avx512f", vector_length = 128, encoding = "evex" }
  { opcode = "EVEX.256.0F.W0 79 /r", form = "VCVTPS2UDQ ymm1{k1}{z}, ymm2/m256/m32bcst", op_en = "A", feature = "avx512vl+avx512f", vector_length = 256, encoding = "evex" }
  { opcode = "EVEX.512.0F.W0 79 /r", form = "VCVTPS2UDQ zmm1{k1}{z}, zmm2/m512/m32bcst", op_en = "A", feature = "avx512f", vector_length = 512, encoding = "evex" }
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
Convert packed single-precision FP32 values to packed unsigned doubleword integers.
"""

handler = "x86_vcvtps2udq"
jit_lowering = "arm64_vcvtps2udq"
fallback = "zig_vcvtps2udq"

neon_register_model = """
x86 XMM/YMM/ZMM mapped to ARM64 Vn. VCVTPS2UDQ is a AVX512 conversion.
"""

neon_flag_model = """
No x86 flags modified by VCVTPS2UDQ.
"""

neon_assembly = """
// NEON lowering: VCVTPS2UDQ conversion stub (avx512_convert)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
