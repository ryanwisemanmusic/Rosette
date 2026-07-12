// UNPCKHPS.inc
// Unpack high-order packed single precision floating-point values.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
UNPCKHPS: unpack and interleave high-order f32 elements from two operands.
Category: simd_float_unpack_high.
"""

name = "UNPCKHPS"
category = "simd_float_unpack_high"
feature = "SSE"
element_type = "f32"
legacy_width = 128
lanes_128 = 4
lanes_256 = 8
lanes_512 = 16
mxcsr_used = true

encodings = [
  { opcode = "NP 0F 15 /r", form = "UNPCKHPS xmm1, xmm2/m128", op_en = "A", feature = "SSE", mode = "V/V", handler = "x86_unpckhps_xmm_xmmm128" },
  { opcode = "VEX.128.0F.WIG 15 /r", form = "VUNPCKHPS xmm1, xmm2, xmm3/m128", op_en = "B", feature = "AVX", mode = "V/V", handler = "x86_vunpckhps_xmm_xmm_xmmm128" },
  { opcode = "VEX.256.0F.WIG 15 /r", form = "VUNPCKHPS ymm1, ymm2, ymm3/m256", op_en = "B", feature = "AVX", mode = "V/V", handler = "x86_vunpckhps_ymm_ymm_ymmm256" },
  { opcode = "EVEX.128.0F.W0 15 /r", form = "VUNPCKHPS xmm1 {k1}{z}, xmm2, xmm3/m128/m32bcst", op_en = "C", feature = "AVX512VL AVX512F", tuple = "Full", handler = "x86_vunpckhps_evex128" },
  { opcode = "EVEX.256.0F.W0 15 /r", form = "VUNPCKHPS ymm1 {k1}{z}, ymm2, ymm3/m256/m32bcst", op_en = "C", feature = "AVX512VL AVX512F", tuple = "Full", handler = "x86_vunpckhps_evex256" },
  { opcode = "EVEX.512.0F.W0 15 /r", form = "VUNPCKHPS zmm1 {k1}{z}, zmm2, zmm3/m512/m32bcst{er}", op_en = "C", feature = "AVX512F", tuple = "Full", handler = "x86_vunpckhps_evex512" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "ModRM:reg (r, w)", operand2 = "ModRM:r/m (r)", operand3 = "N/A", operand4 = "N/A" },
  { op_en = "B", tuple = "N/A", operand1 = "ModRM:reg (w)", operand2 = "VEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "N/A" },
  { op_en = "C", tuple = "Full", operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "N/A" }
]

semantic_legacy = """
DEST.f32[0] = DEST.f32[2];
DEST.f32[1] = DEST.f32[3];
DEST.f32[2] = SRC.f32[2];
DEST.f32[3] = SRC.f32[3];
DEST[MAXVL-1:128] unchanged;
"""

semantic_vex_128 = """
DEST.f32[0] = SRC1.f32[2];
DEST.f32[1] = SRC1.f32[3];
DEST.f32[2] = SRC2.f32[2];
DEST.f32[3] = SRC2.f32[3];
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
DEST.f32[0] = SRC1.f32[2];
DEST.f32[1] = SRC1.f32[3];
DEST.f32[2] = SRC2.f32[2];
DEST.f32[3] = SRC2.f32[3];
DEST.f32[4] = SRC1.f32[6];
DEST.f32[5] = SRC1.f32[7];
DEST.f32[6] = SRC2.f32[6];
DEST.f32[7] = SRC2.f32[7];
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
for each active f32 lane group selected by k1 or no writemask:
    DEST[i * 4 + 0] = SRC1[VL/2 + i * 4 + 0];
    DEST[i * 4 + 1] = SRC1[VL/2 + i * 4 + 1];
    DEST[i * 4 + 2] = SRC2[VL/2 + i * 4 + 0_or_broadcast];
    DEST[i * 4 + 3] = SRC2[VL/2 + i * 4 + 1_or_broadcast];
else merge old destination or zero according to masking mode;
DEST[MAXVL-1:VL] = 0;
"""

simd_fp_exceptions = ["overflow", "underflow", "invalid", "precision", "denormal"]
other_exceptions = ["VEX Type 2 class exceptions", "EVEX Type E2 class exceptions"]

handler = "x86_unpckhps"
jit_lowering = "arm64_neon_zip_high_s"
