// VFPCLASSPD.inc
// TEST VFPCLASSPD — Classify Packed Double-Precision Floating-Point Values

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VFPCLASSPD: test packed double-precision values against the condition specified by imm8, write result to mask register k1.
Category: fp_classify.
"""

name = "VFPCLASSPD"
category = "fp_classify"
feature = "AVX512DQ"
element_type = "f64"

encodings = [
  { opcode = "EVEX.128.66.0F3A.W1 66 /r ib", form = "VFPCLASSPD k1, xmm2/m128/m64bcst, imm8", op_en = "RM", feature = "AVX512DQ", mode = "V/V", handler = "x86_vfpclasspd_xmm_k_m128" },
  { opcode = "EVEX.256.66.0F3A.W1 66 /r ib", form = "VFPCLASSPD k1, ymm2/m256/m64bcst, imm8", op_en = "RM", feature = "AVX512DQ", mode = "V/V", handler = "x86_vfpclasspd_ymm_k_m256" },
  { opcode = "EVEX.512.66.0F3A.W1 66 /r ib", form = "VFPCLASSPD k1, zmm2/m512/m64bcst, imm8", op_en = "RM", feature = "AVX512DQ", mode = "V/V", handler = "x86_vfpclasspd_zmm_k_m512" }
]

operand_encodings = [
  { op_en = "RM", tuple = "Full", operand1 = "ModRM:reg (w)", operand2 = "ModRM:r/m (r)", operand3 = "imm8 (r)", operand4 = "N/A" }
]

simd_fp_exceptions = ["invalid"]
other_exceptions = ["EVEX Type 2 class exceptions"]

handler = "x86_vfpclasspd"
jit_lowering = "arm64_neon_fclass_pd"
