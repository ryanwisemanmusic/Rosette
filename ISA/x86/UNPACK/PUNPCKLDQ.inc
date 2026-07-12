// PUNPCKLDQ.inc
// Unpack low-order doublewords from source and destination operands.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
PUNPCKLDQ: unpack and interleave low-order 32-bit doublewords from two operands.
Category: simd_integer_unpack_low.
"""

name = "PUNPCKLDQ"
category = "simd_integer_unpack_low"
feature = "MMX"
element_type = "i32"
legacy_width = 64
lanes_128 = 4
lanes_256 = 8
lanes_512 = 16
mxcsr_used = false

encodings = [
  { opcode = "NP 0F 62 /r", form = "PUNPCKLDQ mm1, mm2/m64", op_en = "A", feature = "MMX", mode = "V/V", handler = "x86_punpckldq_mm_mmm64" },
  { opcode = "66 0F 62 /r", form = "PUNPCKLDQ xmm1, xmm2/m128", op_en = "A", feature = "SSE2", mode = "V/V", handler = "x86_punpckldq_xmm_xmmm128" },
  { opcode = "VEX.128.66.0F.WIG 62 /r", form = "VPUNPCKLDQ xmm1, xmm2, xmm3/m128", op_en = "B", feature = "AVX", mode = "V/V", handler = "x86_vpunpckldq_xmm_xmm_xmmm128" },
  { opcode = "VEX.256.66.0F.WIG 62 /r", form = "VPUNPCKLDQ ymm1, ymm2, ymm3/m256", op_en = "B", feature = "AVX2", mode = "V/V", handler = "x86_vpunpckldq_ymm_ymm_ymmm256" },
  { opcode = "EVEX.128.66.0F.W0 62 /r", form = "VPUNPCKLDQ xmm1 {k1}{z}, xmm2, xmm3/m128/m32bcst", op_en = "C", feature = "AVX512F AVX512VL", tuple = "Full", handler = "x86_vpunpckldq_evex128" },
  { opcode = "EVEX.256.66.0F.W0 62 /r", form = "VPUNPCKLDQ ymm1 {k1}{z}, ymm2, ymm3/m256/m32bcst", op_en = "C", feature = "AVX512F AVX512VL", tuple = "Full", handler = "x86_vpunpckldq_evex256" },
  { opcode = "EVEX.512.66.0F.W0 62 /r", form = "VPUNPCKLDQ zmm1 {k1}{z}, zmm2, zmm3/m512/m32bcst", op_en = "C", feature = "AVX512F", tuple = "Full", handler = "x86_vpunpckldq_evex512" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "ModRM:reg (r, w)", operand2 = "ModRM:r/m (r)", operand3 = "N/A", operand4 = "N/A" },
  { op_en = "B", tuple = "N/A", operand1 = "ModRM:reg (w)", operand2 = "VEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "N/A" },
  { op_en = "C", tuple = "Full", operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "N/A" }
]

semantic_legacy = """
for lane in 0..1:
    DEST.i32[lane * 2] = DEST.i32[lane];
    DEST.i32[lane * 2 + 1] = SRC.i32[lane];
DEST[MAXVL-1:64] unchanged;
"""

semantic_vex_128 = """
for lane in 0..2:
    DEST.i32[lane * 2] = SRC1.i32[lane];
    DEST.i32[lane * 2 + 1] = SRC2.i32[lane];
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
for lane in 0..4:
    DEST.i32[lane * 2] = SRC1.i32[lane];
    DEST.i32[lane * 2 + 1] = SRC2.i32[lane];
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
for each active i32 lane group selected by k1 or no writemask:
    DEST[i * 2 + 0] = SRC1[i];
    DEST[i * 2 + 1] = SRC2[i_or_broadcast];
else merge old destination or zero according to masking mode;
DEST[MAXVL-1:VL] = 0;
"""

simd_fp_exceptions = []
other_exceptions = ["Non-EVEX: Type 4 class exceptions", "EVEX: Type E4 class exceptions"]

handler = "x86_punpckldq"
jit_lowering = "arm64_neon_zip_low_s"
