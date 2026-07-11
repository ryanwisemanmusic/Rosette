// PMULHRSW.inc

operand_encoding = [
  { op_en = "A", operand_1 = "ModRM:reg (r, w)", operand_2 = "ModRM:r/m (r)", operand_3 = "N/A", operand_4 = "N/A" },
  { op_en = "B", operand_1 = "ModRM:reg (w)", operand_2 = "VEX.vvvv (r)", operand_3 = "ModRM:r/m (r)", operand_4 = "N/A" },
  { op_en = "C", operand_1 = "ModRM:reg (w)", operand_2 = "EVEX.vvvv (r)", operand_3 = "ModRM:r/m (r)", operand_4 = "N/A" },
]

name = "PMULHRSW"
category = "simd_int_mul_fixed"
feature = "SSSE3"
element_type = "i16"

encodings = [
  { opcode = "NP 0F 38 0B /r", form = "PMULHRSW mm1, mm2/m64", op_en = "A", feature = "SSSE3" },
  { opcode = "66 0F 38 0B /r", form = "PMULHRSW xmm1, xmm2/m128", op_en = "A", feature = "SSSE3" },
  { opcode = "VEX.128.66.0F38.WIG 0B /r", form = "VPMULHRSW xmm1, xmm2, xmm3/m128", op_en = "B", feature = "AVX" },
  { opcode = "VEX.256.66.0F38.WIG 0B /r", form = "VPMULHRSW ymm1, ymm2, ymm3/m256", op_en = "B", feature = "AVX2" },
  { opcode = "EVEX.128.66.0F38.WIG 0B /r", form = "VPMULHRSW xmm1 {k1}{z}, xmm2, xmm3/m128", op_en = "C", feature = "AVX512BW AVX512VL" },
  { opcode = "EVEX.256.66.0F38.WIG 0B /r", form = "VPMULHRSW ymm1 {k1}{z}, ymm2, ymm3/m256", op_en = "C", feature = "AVX512BW AVX512VL" },
  { opcode = "EVEX.512.66.0F38.WIG 0B /r", form = "VPMULHRSW zmm1 {k1}{z}, zmm2, zmm3/m512", op_en = "C", feature = "AVX512BW" },
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
temp[31:0] = INT32(DEST.i16[0] * SRC.i16[0]) >> 14 + 1;
DEST.i16[0] = temp[16:1];
temp[31:0] = INT32(DEST.i16[1] * SRC.i16[1]) >> 14 + 1;
DEST.i16[1] = temp[16:1];
// ... repeat for words 2-7 ...
DEST[MAXVL-1:128] unchanged;
"""

semantic_vex_128 = """
temp[31:0] = INT32(SRC1.i16[0] * SRC2.i16[0]) >> 14 + 1;
DEST.i16[0] = temp[16:1];
temp[31:0] = INT32(SRC1.i16[1] * SRC2.i16[1]) >> 14 + 1;
DEST.i16[1] = temp[16:1];
// ... repeat for words 2-7 ...
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
temp[31:0] = INT32(SRC1.i16[0] * SRC2.i16[0]) >> 14 + 1;
DEST.i16[0] = temp[16:1];
// ... repeat for words 1-15 ...
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
(KL, VL) = (8, 128), (16, 256), (32, 512)
FOR j := 0 TO KL-1
    i := j * 16
    IF writemask_enabled:
        temp[31:0] := (SRC1.i16[j] * SRC2.i16[j]) >> 14 + 1
        DEST.i16[j] := tmp[16:1]
    ELSE if zero_masking:
        DEST.i16[j] = 0
DEST[MAXVL-1:VL] = 0
"""

handler = "x86_pmulhrsw"
jit_lowering = "arm64_neon_sqrdmulh"
fallback = "zig_lane_loop"
