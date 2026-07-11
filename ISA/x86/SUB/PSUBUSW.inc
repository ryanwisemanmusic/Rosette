// PSUBUSW.inc
// Subtract packed word integers with unsigned saturation.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
PSUBUSW: subtract packed 16-bit unsigned integer elements with unsigned saturation (result clamped to [0, 65535]).
Category: simd_integer_subtract.
"""

name = "PSUBUSW"
category = "simd_integer_subtract"
feature = "MMX"
element_type = "u16"
legacy_width = 64
lanes_128 = 8
lanes_256 = 16
lanes_512 = 32
mxcsr_used = false

encodings = [
  { opcode = "NP 0F D9 /r", form = "PSUBUSW mm1, mm2/m64", op_en = "A", feature = "MMX", mode = "V/V", handler = "x86_psubusw_mm_mmm64" },
  { opcode = "66 0F D9 /r", form = "PSUBUSW xmm1, xmm2/m128", op_en = "A", feature = "SSE2", mode = "V/V", handler = "x86_psubusw_xmm_xmmm128" },
  { opcode = "VEX.128.66.0F.WIG D9 /r", form = "VPSUBUSW xmm1, xmm2, xmm3/m128", op_en = "B", feature = "AVX", mode = "V/V", handler = "x86_vpsubusw_xmm_xmm_xmmm128" },
  { opcode = "VEX.256.66.0F.WIG D9 /r", form = "VPSUBUSW ymm1, ymm2, ymm3/m256", op_en = "B", feature = "AVX2", mode = "V/V", handler = "x86_vpsubusw_ymm_ymm_ymmm256" },
  { opcode = "EVEX.128.66.0F.WIG D9 /r", form = "VPSUBUSW xmm1 {k1}{z}, xmm2, xmm3/m128", op_en = "C", feature = "AVX512BW AVX512VL", tuple = "Full", handler = "x86_vpsubusw_evex128" },
  { opcode = "EVEX.256.66.0F.WIG D9 /r", form = "VPSUBUSW ymm1 {k1}{z}, ymm2, ymm3/m256", op_en = "C", feature = "AVX512BW AVX512VL", tuple = "Full", handler = "x86_vpsubusw_evex256" },
  { opcode = "EVEX.512.66.0F.WIG D9 /r", form = "VPSUBUSW zmm1 {k1}{z}, zmm2, zmm3/m512", op_en = "C", feature = "AVX512BW", tuple = "Full", handler = "x86_vpsubusw_evex512" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "ModRM:reg (r, w)", operand2 = "ModRM:r/m (r)", operand3 = "N/A", operand4 = "N/A" },
  { op_en = "B", tuple = "N/A", operand1 = "ModRM:reg (w)", operand2 = "VEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "N/A" },
  { op_en = "C", tuple = "Full", operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "N/A" }
]

semantic_legacy = """
for lane in 0..4:
    DEST.u16[lane] = unsigned_saturate(DEST.u16[lane] - SRC.u16[lane], 16);
DEST[MAXVL-1:64] unchanged;
"""

semantic_vex_128 = """
for lane in 0..8:
    DEST.u16[lane] = unsigned_saturate(SRC1.u16[lane] - SRC2.u16[lane], 16);
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
for lane in 0..16:
    DEST.u16[lane] = unsigned_saturate(SRC1.u16[lane] - SRC2.u16[lane], 16);
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
for each active u16 lane selected by k1 or no writemask:
    DEST.u16[lane] = unsigned_saturate(SRC1.u16[lane] - SRC2.u16[lane], 16);
else merge old destination or zero according to masking mode;
DEST[MAXVL-1:VL] = 0;
"""

simd_fp_exceptions = []
other_exceptions = ["Non-EVEX: Type 4 class exceptions", "EVEX: Type E4 class exceptions"]

handler = "x86_psubusw"
jit_lowering = "arm64_neon_subus_w"
