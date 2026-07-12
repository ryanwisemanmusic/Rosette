// UNPCKLPD.inc
// Unpack low-order packed double precision floating-point values.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
UNPCKLPD: unpack and interleave low-order f64 elements from two operands.
Category: simd_float_unpack_low.
"""

name = "UNPCKLPD"
category = "simd_float_unpack_low"
feature = "SSE2"
element_type = "f64"
legacy_width = 128
lanes_128 = 2
lanes_256 = 4
lanes_512 = 8
mxcsr_used = true

encodings = [
  { opcode = "66 0F 14 /r", form = "UNPCKLPD xmm1, xmm2/m128", op_en = "A", feature = "SSE2", mode = "V/V", handler = "x86_unpcklpd_xmm_xmmm128" },
  { opcode = "VEX.128.66.0F.WIG 14 /r", form = "VUNPCKLPD xmm1, xmm2, xmm3/m128", op_en = "B", feature = "AVX", mode = "V/V", handler = "x86_vunpcklpd_xmm_xmm_xmmm128" },
  { opcode = "VEX.256.66.0F.WIG 14 /r", form = "VUNPCKLPD ymm1, ymm2, ymm3/m256", op_en = "B", feature = "AVX", mode = "V/V", handler = "x86_vunpcklpd_ymm_ymm_ymmm256" },
  { opcode = "EVEX.128.66.0F.W1 14 /r", form = "VUNPCKLPD xmm1 {k1}{z}, xmm2, xmm3/m128/m64bcst", op_en = "C", feature = "AVX512VL AVX512F", tuple = "Full", handler = "x86_vunpcklpd_evex128" },
  { opcode = "EVEX.256.66.0F.W1 14 /r", form = "VUNPCKLPD ymm1 {k1}{z}, ymm2, ymm3/m256/m64bcst", op_en = "C", feature = "AVX512VL AVX512F", tuple = "Full", handler = "x86_vunpcklpd_evex256" },
  { opcode = "EVEX.512.66.0F.W1 14 /r", form = "VUNPCKLPD zmm1 {k1}{z}, zmm2, zmm3/m512/m64bcst{er}", op_en = "C", feature = "AVX512F", tuple = "Full", handler = "x86_vunpcklpd_evex512" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "ModRM:reg (r, w)", operand2 = "ModRM:r/m (r)", operand3 = "N/A", operand4 = "N/A" },
  { op_en = "B", tuple = "N/A", operand1 = "ModRM:reg (w)", operand2 = "VEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "N/A" },
  { op_en = "C", tuple = "Full", operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "N/A" }
]

semantic_legacy = """
DEST.f64[0] = DEST.f64[0];
DEST.f64[1] = SRC.f64[0];
DEST[MAXVL-1:128] unchanged;
"""

semantic_vex_128 = """
DEST.f64[0] = SRC1.f64[0];
DEST.f64[1] = SRC2.f64[0];
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
DEST.f64[0] = SRC1.f64[0];
DEST.f64[1] = SRC2.f64[0];
DEST.f64[2] = SRC1.f64[2];
DEST.f64[3] = SRC2.f64[2];
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
for each active f64 lane group selected by k1 or no writemask:
    DEST[i * 2 + 0] = SRC1[VL/4 + i * 2];
    DEST[i * 2 + 1] = SRC2[VL/4 + i * 2_or_broadcast];
else merge old destination or zero according to masking mode;
DEST[MAXVL-1:VL] = 0;
"""

simd_fp_exceptions = ["overflow", "underflow", "invalid", "precision", "denormal"]
other_exceptions = ["VEX Type 2 class exceptions", "EVEX Type E2 class exceptions"]

handler = "x86_unpcklpd"
jit_lowering = "arm64_neon_zip_low_d"
