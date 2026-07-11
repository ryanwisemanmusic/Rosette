// PMULHUW.inc

operand_encoding = [
  { op_en = "A", operand_1 = "ModRM:reg (r, w)", operand_2 = "ModRM:r/m (r)", operand_3 = "N/A", operand_4 = "N/A" },
  { op_en = "B", operand_1 = "ModRM:reg (w)", operand_2 = "VEX.vvvv (r)", operand_3 = "ModRM:r/m (r)", operand_4 = "N/A" },
  { op_en = "C", operand_1 = "ModRM:reg (w)", operand_2 = "EVEX.vvvv (r)", operand_3 = "ModRM:r/m (r)", operand_4 = "N/A" },
]

name = "PMULHUW"
category = "simd_int_mul_high"
feature = "SSE"
element_type = "u16"

encodings = [
  { opcode = "NP 0F E4 /r", form = "PMULHUW mm1, mm2/m64", op_en = "A", feature = "SSE" },
  { opcode = "66 0F E4 /r", form = "PMULHUW xmm1, xmm2/m128", op_en = "A", feature = "SSE2" },
  { opcode = "VEX.128.66.0F.WIG E4 /r", form = "VPMULHUW xmm1, xmm2, xmm3/m128", op_en = "B", feature = "AVX" },
  { opcode = "VEX.256.66.0F.WIG E4 /r", form = "VPMULHUW ymm1, ymm2, ymm3/m256", op_en = "B", feature = "AVX2" },
  { opcode = "EVEX.128.66.0F.WIG E4 /r", form = "VPMULHUW xmm1 {k1}{z}, xmm2, xmm3/m128", op_en = "C", feature = "AVX512BW AVX512VL" },
  { opcode = "EVEX.256.66.0F.WIG E4 /r", form = "VPMULHUW ymm1 {k1}{z}, ymm2, ymm3/m256", op_en = "C", feature = "AVX512BW AVX512VL" },
  { opcode = "EVEX.512.66.0F.WIG E4 /r", form = "VPMULHUW zmm1 {k1}{z}, zmm2, zmm3/m512", op_en = "C", feature = "AVX512BW" },
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
TEMP[31:0] = DEST.u16[0] * SRC.u16[0];
DEST.u16[0] = TEMP[31:16];
TEMP[31:0] = DEST.u16[1] * SRC.u16[1];
DEST.u16[1] = TEMP[31:16];
// ... repeat for words 2-7 ...
DEST[MAXVL-1:128] unchanged;
"""

semantic_vex_128 = """
TEMP[31:0] = SRC1.u16[0] * SRC2.u16[0];
DEST.u16[0] = TEMP[31:16];
TEMP[31:0] = SRC1.u16[1] * SRC2.u16[1];
DEST.u16[1] = TEMP[31:16];
// ... repeat for words 2-7 ...
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
TEMP[31:0] = SRC1.u16[0] * SRC2.u16[0];
DEST.u16[0] = TEMP[31:16];
// ... repeat for words 1-15 ...
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
(KL, VL) = (8, 128), (16, 256), (32, 512)
FOR j := 0 TO KL-1
    i := j * 16
    IF writemask_enabled:
        temp[31:0] := SRC1.u16[j] * SRC2.u16[j]
        DEST.u16[j] := tmp[31:16]
    ELSE if zero_masking:
        DEST.u16[j] = 0
DEST[MAXVL-1:VL] = 0
"""

handler = "x86_pmulhuw"
jit_lowering = "arm64_neon_umull_high"
fallback = "zig_lane_loop"
