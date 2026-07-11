// PSUBB.inc
// Subtract packed byte integers.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
PSUBB: subtract packed 8-bit signed integer elements (wraps on overflow).
Category: simd_integer_subtract.
"""

name = "PSUBB"
category = "simd_integer_subtract"
feature = "MMX"
element_type = "i8"
legacy_width = 64
lanes_128 = 16
lanes_256 = 32
lanes_512 = 64
mxcsr_used = false

encodings = [
  { opcode = "NP 0F F8 /r", form = "PSUBB mm1, mm2/m64", op_en = "A", feature = "MMX", mode = "V/V", handler = "x86_psubb_mm_mmm64" },
  { opcode = "66 0F F8 /r", form = "PSUBB xmm1, xmm2/m128", op_en = "A", feature = "SSE2", mode = "V/V", handler = "x86_psubb_xmm_xmmm128" },
  { opcode = "VEX.128.66.0F.WIG F8 /r", form = "VPSUBB xmm1, xmm2, xmm3/m128", op_en = "B", feature = "AVX", mode = "V/V", handler = "x86_vpsubb_xmm_xmm_xmmm128" },
  { opcode = "VEX.256.66.0F.WIG F8 /r", form = "VPSUBB ymm1, ymm2, ymm3/m256", op_en = "B", feature = "AVX2", mode = "V/V", handler = "x86_vpsubb_ymm_ymm_ymmm256" },
  { opcode = "EVEX.128.66.0F.WIG F8 /r", form = "VPSUBB xmm1 {k1}{z}, xmm2, xmm3/m128", op_en = "C", feature = "AVX512BW AVX512VL", tuple = "Full", handler = "x86_vpsubb_evex128" },
  { opcode = "EVEX.256.66.0F.WIG F8 /r", form = "VPSUBB ymm1 {k1}{z}, ymm2, ymm3/m256", op_en = "C", feature = "AVX512BW AVX512VL", tuple = "Full", handler = "x86_vpsubb_evex256" },
  { opcode = "EVEX.512.66.0F.WIG F8 /r", form = "VPSUBB zmm1 {k1}{z}, zmm2, zmm3/m512", op_en = "C", feature = "AVX512BW", tuple = "Full", handler = "x86_vpsubb_evex512" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "ModRM:reg (r, w)", operand2 = "ModRM:r/m (r)", operand3 = "N/A", operand4 = "N/A" },
  { op_en = "B", tuple = "N/A", operand1 = "ModRM:reg (w)", operand2 = "VEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "N/A" },
  { op_en = "C", tuple = "Full", operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "N/A" }
]

semantic_legacy = """
for lane in 0..8:
    DEST.i8[lane] = DEST.i8[lane] - SRC.i8[lane];
DEST[MAXVL-1:64] unchanged;
"""

semantic_vex_128 = """
for lane in 0..16:
    DEST.i8[lane] = SRC1.i8[lane] - SRC2.i8[lane];
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
for lane in 0..32:
    DEST.i8[lane] = SRC1.i8[lane] - SRC2.i8[lane];
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
for each active i8 lane selected by k1 or no writemask:
    DEST.i8[lane] = SRC1.i8[lane] - SRC2.i8[lane];
else merge old destination or zero according to masking mode;
DEST[MAXVL-1:VL] = 0;
"""

simd_fp_exceptions = []
other_exceptions = ["Non-EVEX: Type 4 class exceptions", "EVEX: Type E4 class exceptions"]

handler = "x86_psubb"
jit_lowering = "arm64_neon_sub_b"
