// VSUBPH.inc
// Subtract packed FP16 values (AVX512-FP16).

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VSUBPH: subtract packed FP16 elements with AVX512-FP16 masking and broadcast.
Category: simd_float_subtract.
"""

name = "VSUBPH"
category = "simd_float_subtract"
feature = "AVX512-FP16"
element_type = "f16"
legacy_width = 128
lanes_128 = 8
lanes_256 = 16
lanes_512 = 32
mxcsr_used = true

encodings = [
  { opcode = "EVEX.128.F3.MAP5.W0 5C /r", form = "VSUBPH xmm1 {k1}{z}, xmm2, xmm3/m128/m16bcst", op_en = "C", feature = "AVX512-FP16 AVX512VL", tuple = "Full", handler = "x86_vsubph_evex128" },
  { opcode = "EVEX.256.F3.MAP5.W0 5C /r", form = "VSUBPH ymm1 {k1}{z}, ymm2, ymm3/m256/m16bcst", op_en = "C", feature = "AVX512-FP16 AVX512VL", tuple = "Full", handler = "x86_vsubph_evex256" },
  { opcode = "EVEX.512.F3.MAP5.W0 5C /r", form = "VSUBPH zmm1 {k1}{z}, zmm2, zmm3/m512/m16bcst{er}", op_en = "C", feature = "AVX512-FP16", tuple = "Full", handler = "x86_vsubph_evex512" }
]

operand_encodings = [
  { op_en = "C", tuple = "Full", operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "N/A" }
]

semantic_evex = """
for each active f16 lane selected by k1 or no writemask:
    DEST.f16[lane] = SRC1.f16[lane] - SRC2.f16[lane_or_broadcast];
else merge old destination or zero according to masking mode;
DEST[MAXVL-1:VL] = 0;
"""

simd_fp_exceptions = ["overflow", "underflow", "invalid", "precision", "denormal"]
other_exceptions = ["EVEX Type E2 class exceptions"]

handler = "x86_vsubph"
jit_lowering = "arm64_neon_fsub_ph"
