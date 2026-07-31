// PMULLW.inc

operand_encoding = [
  { op_en = "A", operand_1 = "ModRM:reg (r, w)", operand_2 = "ModRM:r/m (r)", operand_3 = "N/A", operand_4 = "N/A" },
  { op_en = "B", operand_1 = "ModRM:reg (w)", operand_2 = "VEX.vvvv (r)", operand_3 = "ModRM:r/m (r)", operand_4 = "N/A" },
  { op_en = "C", operand_1 = "ModRM:reg (w)", operand_2 = "EVEX.vvvv (r)", operand_3 = "ModRM:r/m (r)", operand_4 = "N/A" },
]

name = "PMULLW"
category = "simd_int_mul_low"
feature = "MMX"
element_type = "i16"

encodings = [
  { opcode = "NP 0F D5 /r", form = "PMULLW mm, mm/m64", op_en = "A", feature = "MMX" },
  { opcode = "66 0F D5 /r", form = "PMULLW xmm1, xmm2/m128", op_en = "A", feature = "SSE2" },
  { opcode = "VEX.128.66.0F.WIG D5 /r", form = "VPMULLW xmm1, xmm2, xmm3/m128", op_en = "B", feature = "AVX" },
  { opcode = "VEX.256.66.0F.WIG D5 /r", form = "VPMULLW ymm1, ymm2, ymm3/m256", op_en = "B", feature = "AVX2" },
  { opcode = "EVEX.128.66.0F.WIG D5 /r", form = "VPMULLW xmm1 {k1}{z}, xmm2, xmm3/m128", op_en = "C", feature = "AVX512BW AVX512VL" },
  { opcode = "EVEX.256.66.0F.WIG D5 /r", form = "VPMULLW ymm1 {k1}{z}, ymm2, ymm3/m256", op_en = "C", feature = "AVX512BW AVX512VL" },
  { opcode = "EVEX.512.66.0F.WIG D5 /r", form = "VPMULLW zmm1 {k1}{z}, zmm2, zmm3/m512", op_en = "C", feature = "AVX512BW" },
]

element_size = 16
lane_type = "word"

lanes = {
  mmx = 4,
  xmm = 8,
  ymm = 16,
  zmm = 32
}

mxcsr_used = false

simd_fp_exceptions = []

flags_written = []

semantic_legacy_128 = """
TEMP[31:0] = DEST.i16[0] * SRC.i16[0];
DEST.i16[0] = TEMP[15:0];
TEMP[31:0] = DEST.i16[1] * SRC.i16[1];
DEST.i16[1] = TEMP[15:0];
// ... repeat for words 2-7 ...
DEST[MAXVL-1:128] unchanged;
"""

semantic_vex_128 = """
TEMP[31:0] = SRC1.i16[0] * SRC2.i16[0];
DEST.i16[0] = TEMP[15:0];
TEMP[31:0] = SRC1.i16[1] * SRC2.i16[1];
DEST.i16[1] = TEMP[15:0];
// ... repeat for words 2-7 ...
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
TEMP[31:0] = SRC1.i16[0] * SRC2.i16[0];
DEST.i16[0] = TEMP[15:0];
// ... repeat for words 1-15 ...
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
(KL, VL) = (8, 128), (16, 256), (32, 512)
FOR j := 0 TO KL-1
    i := j * 16
    IF writemask_enabled:
        temp[31:0] := SRC1.i16[j] * SRC2.i16[j]
        DEST.i16[j] := tmp[15:0]
    ELSE if zero_masking:
        DEST.i16[j] = 0
DEST[MAXVL-1:VL] = 0
"""

handler = "x86_pmullw"
jit_lowering = "arm64_neon_mul_v8i16"
fallback = "zig_lane_loop"

semantic_general = """
PMULLW: preserve the x86 operation contract; see the x86 source table for the full semantic blocks.
"""
