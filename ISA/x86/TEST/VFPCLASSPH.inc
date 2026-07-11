// VFPCLASSPH.inc
// TEST VFPCLASSPH — Classify Packed Half-Precision Floating-Point Values

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VFPCLASSPH: test packed half-precision values against the condition specified by imm8, write result to mask register k1.
Category: fp_classify.
"""

name = "VFPCLASSPH"
category = "fp_classify"
feature = "AVX512-FP16"
element_type = "f16"

encodings = [
  { opcode = "EVEX.128.NP.0F3A.W0 66 /r /ib", form = "VFPCLASSPH k1, xmm2/m128, imm8", op_en = "RM", feature = "AVX512-FP16", mode = "V/V", handler = "x86_vfpclassph_xmm_k_m128" },
  { opcode = "EVEX.256.NP.0F3A.W0 66 /r /ib", form = "VFPCLASSPH k1, ymm2/m256, imm8", op_en = "RM", feature = "AVX512-FP16", mode = "V/V", handler = "x86_vfpclassph_ymm_k_m256" },
  { opcode = "EVEX.512.NP.0F3A.W0 66 /r /ib", form = "VFPCLASSPH k1, zmm2/m512, imm8", op_en = "RM", feature = "AVX512-FP16", mode = "V/V", handler = "x86_vfpclassph_zmm_k_m512" }
]

operand_encodings = [
  { op_en = "RM", tuple = "Full", operand1 = "ModRM:reg (w)", operand2 = "ModRM:r/m (r)", operand3 = "imm8 (r)", operand4 = "N/A" }
]

simd_fp_exceptions = ["invalid"]
other_exceptions = ["EVEX Type 2 class exceptions"]

handler = "x86_vfpclassph"
jit_lowering = "arm64_neon_fclass_ph"
