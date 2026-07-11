// PSUBQ.inc
// Subtract packed quadword integers.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
PSUBQ: subtract packed 64-bit signed integer elements (wraps on overflow).
Category: simd_integer_subtract.
"""

name = "PSUBQ"
category = "simd_integer_subtract"
feature = "SSE2"
element_type = "i64"
legacy_width = 64
lanes_128 = 2
lanes_256 = 4
lanes_512 = 8
mxcsr_used = false

encodings = [
  { opcode = "NP 0F FB /r", form = "PSUBQ mm1, mm2/m64", op_en = "A", feature = "SSE2", mode = "V/V", handler = "x86_psubq_mm_mmm64" },
  { opcode = "66 0F FB /r", form = "PSUBQ xmm1, xmm2/m128", op_en = "A", feature = "SSE2", mode = "V/V", handler = "x86_psubq_xmm_xmmm128" },
  { opcode = "VEX.128.66.0F.WIG FB /r", form = "VPSUBQ xmm1, xmm2, xmm3/m128", op_en = "B", feature = "AVX", mode = "V/V", handler = "x86_vpsubq_xmm_xmm_xmmm128" },
  { opcode = "VEX.256.66.0F.WIG FB /r", form = "VPSUBQ ymm1, ymm2, ymm3/m256", op_en = "B", feature = "AVX2", mode = "V/V", handler = "x86_vpsubq_ymm_ymm_ymmm256" },
  { opcode = "EVEX.128.66.0F.W1 FB /r", form = "VPSUBQ xmm1 {k1}{z}, xmm2, xmm3/m128/m64bcst", op_en = "C", feature = "AVX512F AVX512VL", tuple = "Full", handler = "x86_vpsubq_evex128" },
  { opcode = "EVEX.256.66.0F.W1 FB /r", form = "VPSUBQ ymm1 {k1}{z}, ymm2, ymm3/m256/m64bcst", op_en = "C", feature = "AVX512F AVX512VL", tuple = "Full", handler = "x86_vpsubq_evex256" },
  { opcode = "EVEX.512.66.0F.W1 FB /r", form = "VPSUBQ zmm1 {k1}{z}, zmm2, zmm3/m512/m64bcst", op_en = "C", feature = "AVX512F", tuple = "Full", handler = "x86_vpsubq_evex512" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "ModRM:reg (r, w)", operand2 = "ModRM:r/m (r)", operand3 = "N/A", operand4 = "N/A" },
  { op_en = "B", tuple = "N/A", operand1 = "ModRM:reg (w)", operand2 = "VEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "N/A" },
  { op_en = "C", tuple = "Full", operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "N/A" }
]

semantic_legacy = """
DEST.i64[0] = DEST.i64[0] - SRC.i64[0];
DEST[MAXVL-1:64] unchanged;
"""

semantic_vex_128 = """
DEST.i64[0] = SRC1.i64[0] - SRC2.i64[0];
DEST.i64[1] = SRC1.i64[1] - SRC2.i64[1];
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
for lane in 0..4:
    DEST.i64[lane] = SRC1.i64[lane] - SRC2.i64[lane];
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
for each active i64 lane selected by k1 or no writemask:
    DEST.i64[lane] = SRC1.i64[lane] - SRC2.i64[lane_or_broadcast];
else merge old destination or zero according to masking mode;
DEST[MAXVL-1:VL] = 0;
"""

simd_fp_exceptions = []
other_exceptions = ["Non-EVEX: Type 4 class exceptions", "EVEX: Type E4 class exceptions"]

handler = "x86_psubq"
jit_lowering = "arm64_neon_sub_q"
