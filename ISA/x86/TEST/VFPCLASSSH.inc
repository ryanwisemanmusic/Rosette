// VFPCLASSSH.inc
// TEST VFPCLASSSH — Classify Scalar Half-Precision Floating-Point Value

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VFPCLASSSH: test scalar half-precision value against the condition specified by imm8, write result to mask register k1 (bit 0).
Category: fp_classify.
"""

name = "VFPCLASSSH"
category = "fp_classify"
feature = "AVX512-FP16"
element_type = "f16"

encodings = [
  { opcode = "EVEX.LLIG.NP.0F3A.W0 67 /r /ib", form = "VFPCLASSSH k1, xmm2/m16, imm8", op_en = "RM", feature = "AVX512-FP16", mode = "V/V", handler = "x86_vfpclasssh_xmm_k_m16" }
]

operand_encodings = [
  { op_en = "RM", tuple = "Full", operand1 = "ModRM:reg (w)", operand2 = "ModRM:r/m (r)", operand3 = "imm8 (r)", operand4 = "N/A" }
]

simd_fp_exceptions = ["invalid"]
other_exceptions = ["EVEX Type 2 class exceptions"]

handler = "x86_vfpclasssh"
jit_lowering = "arm64_neon_fclass_sh"
