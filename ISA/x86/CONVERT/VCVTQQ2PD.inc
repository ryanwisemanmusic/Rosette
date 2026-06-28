// CONVERT/VCVTQQ2PD.inc
// ARM64/NEON translation mirror generated from ISA/x86/CONVERT/VCVTQQ2PD.inc.
// Source contract: VCVTQQ2PD — Convert Packed Qword to Packed Double.

semantic = """
xmm1 := Convert_Packed_Qword_To_Packed_Double(xmm2/m128/m64bcst)
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/VCVTQQ2PD.inc"
x86_handler = "x86_vcvtqq2pd"
neon_lowering = "arm64_vcvtqq2pd"
lowering_kind = "arm64_documented_contract"

name = "VCVTQQ2PD"
aliases = []
category = "avx512_convert"
feature = "avx512f"
element_type = "f64"
element_size = 64

encodings = [
  { opcode = "EVEX.128.F3.0F.W1 E6 /r", form = "VCVTQQ2PD xmm1{k1}{z}, xmm2/m128/m64bcst", op_en = "A", feature = "avx512vl+avx512f", vector_length = 128, encoding = "evex" }
  { opcode = "EVEX.256.F3.0F.W1 E6 /r", form = "VCVTQQ2PD ymm1{k1}{z}, ymm2/m256/m64bcst", op_en = "A", feature = "avx512vl+avx512f", vector_length = 256, encoding = "evex" }
  { opcode = "EVEX.512.F3.0F.W1 E6 /r", form = "VCVTQQ2PD zmm1{k1}{z}, zmm2/m512/m64bcst", op_en = "A", feature = "avx512f", vector_length = 512, encoding = "evex" }
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
Convert packed quadword integers to packed double-precision FP64 values.
"""

handler = "x86_vcvtqq2pd"
jit_lowering = "arm64_vcvtqq2pd"
fallback = "zig_vcvtqq2pd"

neon_register_model = """
x86 XMM/YMM/ZMM mapped to ARM64 Vn. VCVTQQ2PD is a AVX512 conversion.
"""

neon_flag_model = """
No x86 flags modified by VCVTQQ2PD.
"""

neon_assembly = """
// NEON lowering: VCVTQQ2PD conversion stub (avx512_convert)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
