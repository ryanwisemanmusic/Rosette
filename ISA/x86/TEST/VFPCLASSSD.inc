// VFPCLASSSD.inc
// TEST VFPCLASSSD — Classify Scalar Double-Precision Floating-Point Value

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VFPCLASSSD: test scalar double-precision value against the condition specified by imm8, write result to mask register k1 (bit 0).
Category: fp_classify.
"""

name = "VFPCLASSSD"
category = "fp_classify"
feature = "AVX512DQ"
element_type = "f64"

encodings = [
  { opcode = "EVEX.LLIG.66.0F3A.W1 67 /r ib", form = "VFPCLASSSD k1, xmm2/m64, imm8", op_en = "RM", feature = "AVX512DQ", mode = "V/V", handler = "x86_vfpclasssd_xmm_k_m64" }
]

operand_encodings = [
  { op_en = "RM", tuple = "Full", operand1 = "ModRM:reg (w)", operand2 = "ModRM:r/m (r)", operand3 = "imm8 (r)", operand4 = "N/A" }
]

simd_fp_exceptions = ["invalid"]
other_exceptions = ["EVEX Type 2 class exceptions"]

handler = "x86_vfpclasssd"
jit_lowering = "arm64_neon_fclass_sd"
