// PMADDWD.inc

operand_encoding = [
  { op_en = "A", operand_1 = "ModRM:reg (r, w)", operand_2 = "ModRM:r/m (r)", operand_3 = "N/A", operand_4 = "N/A" },
  { op_en = "B", operand_1 = "ModRM:reg (w)", operand_2 = "VEX.vvvv (r)", operand_3 = "ModRM:r/m (r)", operand_4 = "N/A" },
  { op_en = "C", operand_1 = "ModRM:reg (w)", operand_2 = "EVEX.vvvv (r)", operand_3 = "ModRM:r/m (r)", operand_4 = "N/A" },
]

name = "PMADDWD"
category = "simd_int_mul_add"
feature = "MMX"
element_type = "i16"

encodings = [
  { opcode = "NP 0F F5 /r", form = "PMADDWD mm, mm/m64", op_en = "A", feature = "MMX" },
  { opcode = "66 0F F5 /r", form = "PMADDWD xmm1, xmm2/m128", op_en = "A", feature = "SSE2" },
  { opcode = "VEX.128.66.0F.WIG F5 /r", form = "VPMADDWD xmm1, xmm2, xmm3/m128", op_en = "B", feature = "AVX" },
  { opcode = "VEX.256.66.0F.WIG F5 /r", form = "VPMADDWD ymm1, ymm2, ymm3/m256", op_en = "B", feature = "AVX2" },
  { opcode = "EVEX.128.66.0F.WIG F5 /r", form = "VPMADDWD xmm1 {k1}{z}, xmm2, xmm3/m128", op_en = "C", feature = "AVX512BW AVX512VL" },
  { opcode = "EVEX.256.66.0F.WIG F5 /r", form = "VPMADDWD ymm1 {k1}{z}, ymm2, ymm3/m256", op_en = "C", feature = "AVX512BW AVX512VL" },
  { opcode = "EVEX.512.66.0F.WIG F5 /r", form = "VPMADDWD zmm1 {k1}{z}, ymm2, ymm3/m512", op_en = "C", feature = "AVX512BW" },
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
DEST.i32[0] = (DEST.i16[0] * SRC.i16[0]) + (DEST.i16[1] * SRC.i16[1]);
DEST.i32[1] = (DEST.i16[2] * SRC.i16[2]) + (DEST.i16[3] * SRC.i16[3]);
DEST.i32[2] = (DEST.i16[4] * SRC.i16[4]) + (DEST.i16[5] * SRC.i16[5]);
DEST.i32[3] = (DEST.i16[6] * SRC.i16[6]) + (DEST.i16[7] * SRC.i16[7]);
DEST[MAXVL-1:128] unchanged;
"""

semantic_vex_128 = """
DEST.i32[0] = (SRC1.i16[0] * SRC2.i16[0]) + (SRC1.i16[1] * SRC2.i16[1]);
DEST.i32[1] = (SRC1.i16[2] * SRC2.i16[2]) + (SRC1.i16[3] * SRC2.i16[3]);
DEST.i32[2] = (SRC1.i16[4] * SRC2.i16[4]) + (SRC1.i16[5] * SRC2.i16[5]);
DEST.i32[3] = (SRC1.i16[6] * SRC2.i16[6]) + (SRC1.i16[7] * SRC2.i16[7]);
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
DEST.i32[0] = (SRC1.i16[0] * SRC2.i16[0]) + (SRC1.i16[1] * SRC2.i16[1]);
DEST.i32[1] = (SRC1.i16[2] * SRC2.i16[2]) + (SRC1.i16[3] * SRC2.i16[3]);
DEST.i32[2] = (SRC1.i16[4] * SRC2.i16[4]) + (SRC1.i16[5] * SRC2.i16[5]);
DEST.i32[3] = (SRC1.i16[6] * SRC2.i16[6]) + (SRC1.i16[7] * SRC2.i16[7]);
DEST.i32[4] = (SRC1.i16[8] * SRC2.i16[8]) + (SRC1.i16[9] * SRC2.i16[9]);
DEST.i32[5] = (SRC1.i16[10] * SRC2.i16[10]) + (SRC1.i16[11] * SRC2.i16[11]);
DEST.i32[6] = (SRC1.i16[12] * SRC2.i16[12]) + (SRC1.i16[13] * SRC2.i16[13]);
DEST.i32[7] = (SRC1.i16[14] * SRC2.i16[14]) + (SRC1.i16[15] * SRC2.i16[15]);
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
(KL, VL) = (4, 128), (8, 256), (16, 512)
FOR j := 0 TO KL-1
    i := j * 32
    IF writemask_enabled:
        DEST.i32[j] := (SRC2.i16[i/2] * SRC1.i16[i/2]) + (SRC2.i16[i/2+1] * SRC1.i16[i/2+1])
    ELSE if zero_masking:
        DEST.i32[j] = 0
DEST[MAXVL-1:VL] = 0
"""

handler = "x86_pmaddwd"
jit_lowering = "arm64_neon_smull_add"
fallback = "zig_lane_loop"
