// VFPCLASSPS.inc
// TEST VFPCLASSPS — Classify Packed Single-Precision Floating-Point Values

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VFPCLASSPS: test packed single-precision values against the condition specified by imm8, write result to mask register k1.
Category: fp_classify.
"""

name = "VFPCLASSPS"
category = "fp_classify"
feature = "AVX512DQ"
element_type = "f32"

encodings = [
  { opcode = "EVEX.128.66.0F3A.W0 66 /r ib", form = "VFPCLASSPS k1, xmm2/m128/m32bcst, imm8", op_en = "RM", feature = "AVX512DQ", mode = "V/V", handler = "x86_vfpclassps_xmm_k_m128" },
  { opcode = "EVEX.256.66.0F3A.W0 66 /r ib", form = "VFPCLASSPS k1, ymm2/m256/m32bcst, imm8", op_en = "RM", feature = "AVX512DQ", mode = "V/V", handler = "x86_vfpclassps_ymm_k_m256" },
  { opcode = "EVEX.512.66.0F3A.W0 66 /r ib", form = "VFPCLASSPS k1, zmm2/m512/m32bcst, imm8", op_en = "RM", feature = "AVX512DQ", mode = "V/V", handler = "x86_vfpclassps_zmm_k_m512" }
]

operand_encodings = [
  { op_en = "RM", tuple = "Full", operand1 = "ModRM:reg (w)", operand2 = "ModRM:r/m (r)", operand3 = "imm8 (r)", operand4 = "N/A" }
]

simd_fp_exceptions = ["invalid"]
other_exceptions = ["EVEX Type 2 class exceptions"]

handler = "x86_vfpclassps"
jit_lowering = "arm64_neon_fclass_ps"
