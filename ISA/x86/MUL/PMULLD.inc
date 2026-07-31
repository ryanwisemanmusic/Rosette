// PMULLD.inc

operand_encoding = [
  { op_en = "A", operand_1 = "ModRM:reg (r, w)", operand_2 = "ModRM:r/m (r)", operand_3 = "N/A", operand_4 = "N/A" },
  { op_en = "B", operand_1 = "ModRM:reg (w)", operand_2 = "VEX.vvvv (r)", operand_3 = "ModRM:r/m (r)", operand_4 = "N/A" },
  { op_en = "C", operand_1 = "ModRM:reg (w)", operand_2 = "EVEX.vvvv (r)", operand_3 = "ModRM:r/m (r)", operand_4 = "N/A" },
]

name = "PMULLD"
category = "simd_int_mul_low"
feature = "SSE4_1"
element_type = "i32"

encodings = [
  { opcode = "66 0F 38 40 /r", form = "PMULLD xmm1, xmm2/m128", op_en = "A", feature = "SSE4_1" },
  { opcode = "VEX.128.66.0F38.WIG 40 /r", form = "VPMULLD xmm1, xmm2, xmm3/m128", op_en = "B", feature = "AVX" },
  { opcode = "VEX.256.66.0F38.WIG 40 /r", form = "VPMULLD ymm1, ymm2, ymm3/m256", op_en = "B", feature = "AVX2" },
  { opcode = "EVEX.128.66.0F38.W0 40 /r", form = "VPMULLD xmm1 {k1}{z}, xmm2, xmm3/m128/m32bcst", op_en = "C", feature = "AVX512F AVX512VL" },
  { opcode = "EVEX.256.66.0F38.W0 40 /r", form = "VPMULLD ymm1 {k1}{z}, ymm2, ymm3/m256/m32bcst", op_en = "C", feature = "AVX512F AVX512VL" },
  { opcode = "EVEX.512.66.0F38.W0 40 /r", form = "VPMULLD zmm1 {k1}{z}, zmm2, zmm3/m512/m32bcst", op_en = "C", feature = "AVX512F" },
]

element_size = 32
lane_type = "doubleword"

lanes = {
  xmm = 4,
  ymm = 8,
  zmm = 16
}

mxcsr_used = false

simd_fp_exceptions = []

flags_written = []

semantic_legacy_128 = """
Temp0[63:0] = DEST.i32[0] * SRC.i32[0];
DEST.i32[0] = Temp0[31:0];
Temp1[63:0] = DEST.i32[1] * SRC.i32[1];
DEST.i32[1] = Temp1[31:0];
Temp2[63:0] = DEST.i32[2] * SRC.i32[2];
DEST.i32[2] = Temp2[31:0];
Temp3[63:0] = DEST.i32[3] * SRC.i32[3];
DEST.i32[3] = Temp3[31:0];
DEST[MAXVL-1:128] (Unmodified)
"""

semantic_vex_128 = """
Temp0[63:0] = SRC1.i32[0] * SRC2.i32[0];
DEST.i32[0] = Temp0[31:0];
Temp1[63:0] = SRC1.i32[1] * SRC2.i32[1];
DEST.i32[1] = Temp1[31:0];
Temp2[63:0] = SRC1.i32[2] * SRC2.i32[2];
DEST.i32[2] = Temp2[31:0];
Temp3[63:0] = SRC1.i32[3] * SRC2.i32[3];
DEST.i32[3] = Temp3[31:0];
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
Temp0[63:0] = SRC1.i32[0] * SRC2.i32[0];
DEST.i32[0] = Temp0[31:0];
Temp1[63:0] = SRC1.i32[1] * SRC2.i32[1];
DEST.i32[1] = Temp1[31:0];
Temp2[63:0] = SRC1.i32[2] * SRC2.i32[2];
DEST.i32[2] = Temp2[31:0];
Temp3[63:0] = SRC1.i32[3] * SRC2.i32[3];
DEST.i32[3] = Temp3[31:0];
Temp4[63:0] = SRC1.i32[4] * SRC2.i32[4];
DEST.i32[4] = Temp4[31:0];
Temp5[63:0] = SRC1.i32[5] * SRC2.i32[5];
DEST.i32[5] = Temp5[31:0];
Temp6[63:0] = SRC1.i32[6] * SRC2.i32[6];
DEST.i32[6] = Temp6[31:0];
Temp7[63:0] = SRC1.i32[7] * SRC2.i32[7];
DEST.i32[7] = Temp7[31:0];
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
(KL, VL) = (4, 128), (8, 256), (16, 512)
FOR j := 0 TO KL-1
    i := j * 32
    IF writemask_enabled:
        IF broadcasting and SRC2 is memory:
            Temp[63:0] := SRC1.i32[j] * SRC2.i32[0]
        ELSE:
            Temp[63:0] := SRC1.i32[j] * SRC2.i32[j]
        DEST.i32[j] := Temp[31:0]
    ELSE if zero_masking:
        DEST.i32[j] = 0
DEST[MAXVL-1:VL] = 0
"""

handler = "x86_pmulld"
jit_lowering = "arm64_neon_mul_v4i32"
fallback = "zig_lane_loop"

semantic_general = """
PMULLD: preserve the x86 operation contract; see the x86 source table for the full semantic blocks.
"""
