// VFPCLASSSS.inc
// TEST VFPCLASSSS — Classify Scalar Single-Precision Floating-Point Value

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VFPCLASSSS: test scalar single-precision value against the condition specified by imm8, write result to mask register k1 (bit 0).
Category: fp_classify.
"""

name = "VFPCLASSSS"
category = "fp_classify"
feature = "AVX512DQ"
element_type = "f32"

encodings = [
  { opcode = "EVEX.LLIG.66.0F3A.W0 67 /r ib", form = "VFPCLASSSS k1, xmm2/m32, imm8", op_en = "RM", feature = "AVX512DQ", mode = "V/V", handler = "x86_vfpclassss_xmm_k_m32" }
]

operand_encodings = [
  { op_en = "RM", tuple = "Full", operand1 = "ModRM:reg (w)", operand2 = "ModRM:r/m (r)", operand3 = "imm8 (r)", operand4 = "N/A" }
]

simd_fp_exceptions = ["invalid"]
other_exceptions = ["EVEX Type 2 class exceptions"]

handler = "x86_vfpclassss"
jit_lowering = "arm64_neon_fclass_ss"
