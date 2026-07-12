// UNPCKLPS.inc
// Unpack low-order packed single precision floating-point values.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
UNPCKLPS: unpack and interleave low-order f32 elements from two operands.
Category: simd_float_unpack_low.
"""

name = "UNPCKLPS"
category = "simd_float_unpack_low"
feature = "SSE"
element_type = "f32"
legacy_width = 128
lanes_128 = 4
lanes_256 = 8
lanes_512 = 16
mxcsr_used = true

encodings = [
  { opcode = "NP 0F 14 /r", form = "UNPCKLPS xmm1, xmm2/m128", op_en = "A", feature = "SSE", mode = "V/V", handler = "x86_unpcklps_xmm_xmmm128" },
  { opcode = "VEX.128.0F.WIG 14 /r", form = "VUNPCKLPS xmm1, xmm2, xmm3/m128", op_en = "B", feature = "AVX", mode = "V/V", handler = "x86_vunpcklps_xmm_xmm_xmmm128" },
  { opcode = "VEX.256.0F.WIG 14 /r", form = "VUNPCKLPS ymm1, ymm2, ymm3/m256", op_en = "B", feature = "AVX", mode = "V/V", handler = "x86_vunpcklps_ymm_ymm_ymmm256" },
  { opcode = "EVEX.128.0F.W0 14 /r", form = "VUNPCKLPS xmm1 {k1}{z}, xmm2, xmm3/m128/m32bcst", op_en = "C", feature = "AVX512VL AVX512F", tuple = "Full", handler = "x86_vunpcklps_evex128" },
  { opcode = "EVEX.256.0F.W0 14 /r", form = "VUNPCKLPS ymm1 {k1}{z}, ymm2, ymm3/m256/m32bcst", op_en = "C", feature = "AVX512VL AVX512F", tuple = "Full", handler = "x86_vunpcklps_evex256" },
  { opcode = "EVEX.512.0F.W0 14 /r", form = "VUNPCKLPS zmm1 {k1}{z}, zmm2, zmm3/m512/m32bcst{er}", op_en = "C", feature = "AVX512F", tuple = "Full", handler = "x86_vunpcklps_evex512" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "ModRM:reg (r, w)", operand2 = "ModRM:r/m (r)", operand3 = "N/A", operand4 = "N/A" },
  { op_en = "B", tuple = "N/A", operand1 = "ModRM:reg (w)", operand2 = "VEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "N/A" },
  { op_en = "C", tuple = "Full", operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "N/A" }
]

semantic_legacy = """
DEST.f32[0] = DEST.f32[0];
DEST.f32[1] = DEST.f32[1];
DEST.f32[2] = SRC.f32[0];
DEST.f32[3] = SRC.f32[1];
DEST[MAXVL-1:128] unchanged;
"""

semantic_vex_128 = """
DEST.f32[0] = SRC1.f32[0];
DEST.f32[1] = SRC1.f32[1];
DEST.f32[2] = SRC2.f32[0];
DEST.f32[3] = SRC2.f32[1];
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
DEST.f32[0] = SRC1.f32[0];
DEST.f32[1] = SRC1.f32[1];
DEST.f32[2] = SRC2.f32[0];
DEST.f32[3] = SRC2.f32[1];
DEST.f32[4] = SRC1.f32[4];
DEST.f32[5] = SRC1.f32[5];
DEST.f32[6] = SRC2.f32[4];
DEST.f32[7] = SRC2.f32[5];
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
for each active f32 lane group selected by k1 or no writemask:
    DEST[i * 4 + 0] = SRC1[VL/4 + i * 4 + 0];
    DEST[i * 4 + 1] = SRC1[VL/4 + i * 4 + 1];
    DEST[i * 4 + 2] = SRC2[VL/4 + i * 4 + 0_or_broadcast];
    DEST[i * 4 + 3] = SRC2[VL/4 + i * 4 + 1_or_broadcast];
else merge old destination or zero according to masking mode;
DEST[MAXVL-1:VL] = 0;
"""

simd_fp_exceptions = ["overflow", "underflow", "invalid", "precision", "denormal"]
other_exceptions = ["VEX Type 2 class exceptions", "EVEX Type E2 class exceptions"]

handler = "x86_unpcklps"
jit_lowering = "arm64_neon_zip_low_s"
