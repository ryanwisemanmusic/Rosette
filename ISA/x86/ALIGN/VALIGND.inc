// ALIGN/VALIGND.inc
// Source contract: VALIGND — Align Doubleword Vectors.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ALIGN/VALIGND.inc"
x86_handler = "x86_valignd"
neon_lowering = "arm64_valignd"
lowering_kind = "arm64_documented_contract"

name = "VALIGND"
aliases = []
category = "avx512_align"
feature = "avx512f"
element_type = "i32"
element_size = 32

encodings = [
  { opcode = "EVEX.128.66.0F3A.W0 03 /r ib", form = "VALIGND xmm1 {k1}{z}, xmm2, xmm3/m128/m32bcst, imm8", op_en = "A", feature = "avx512vl+avx512f", vector_length = 0, encoding = "legacy" },
  { opcode = "EVEX.256.66.0F3A.W0 03 /r ib", form = "VALIGND ymm1 {k1}{z}, ymm2, ymm3/m256/m32bcst, imm8", op_en = "A", feature = "avx512vl+avx512f", vector_length = 0, encoding = "legacy" },
  { opcode = "EVEX.512.66.0F3A.W0 03 /r ib", form = "VALIGND zmm1 {k1}{z}, zmm2, zmm3/m512/m32bcst, imm8", op_en = "A", feature = "avx512f", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)"]
}

lanes = { xmm = 1, ymm = 1, zmm = 1 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "See Table 2-50, Type E4NF Class Exception Conditions."
]

semantic_general = """
Concatenates first and second source operands, shifts right by imm8 doubleword elements, and writes the low VL bits to the destination under writemask k1.
"""

handler = "x86_valignd"
jit_lowering = "arm64_valignd"
fallback = "zig_valignd"

neon_register_model = """
VALIGND is an AVX512 alignment operation.
"""

neon_flag_model = """
VALIGND does not modify flags.
"""

neon_assembly = """
// NEON lowering: VALIGND stub (AVX512 align dword)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
