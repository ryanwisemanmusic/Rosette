// PCLMULQDQ.inc

operand_encoding = [
  { op_en = "A", operand_1 = "ModRM:reg (r, w)", operand_2 = "ModRM:r/m (r)", operand_3 = "imm8", operand_4 = "N/A" },
  { op_en = "B", operand_1 = "ModRM:reg (w)", operand_2 = "VEX.vvvv (r)", operand_3 = "ModRM:r/m (r)", operand_4 = "imm8" },
  { op_en = "C", operand_1 = "ModRM:reg (w)", operand_2 = "EVEX.vvvv (r)", operand_3 = "ModRM:r/m (r)", operand_4 = "imm8 (r)" },
]

name = "PCLMULQDQ"
category = "simd_int_mul"
feature = "PCLMULQDQ"
element_type = "i64"

encodings = [
  { opcode = "66 0F 3A 44 /r ib", form = "PCLMULQDQ xmm1, xmm2/m128, imm8", op_en = "A", feature = "PCLMULQDQ" },
  { opcode = "VEX.128.66.0F3A.WIG 44 /r ib", form = "VPCLMULQDQ xmm1, xmm2, xmm3/m128, imm8", op_en = "B", feature = "VPCLMULQDQ" },
  { opcode = "VEX.256.66.0F3A.WIG 44 /r ib", form = "VPCLMULQDQ ymm1, ymm2, ymm3/m256, imm8", op_en = "B", feature = "VPCLMULQDQ" },
  { opcode = "EVEX.128.66.0F3A.WIG 44 /r ib", form = "VPCLMULQDQ xmm1, xmm2, xmm3/m128, imm8", op_en = "C", feature = "VPCLMULQDQ AVX512VL" },
  { opcode = "EVEX.256.66.0F3A.WIG 44 /r ib", form = "VPCLMULQDQ ymm1, ymm2, ymm3/m256, imm8", op_en = "C", feature = "VPCLMULQDQ AVX512VL" },
  { opcode = "EVEX.512.66.0F3A.WIG 44 /r ib", form = "VPCLMULQDQ zmm1, zmm2, zmm3/m512, imm8", op_en = "C", feature = "VPCLMULQDQ AVX512F" },
]

element_size = 64
lane_type = "quadword"

lanes = {
  xmm = 2,
  ymm = 4,
  zmm = 8
}

mxcsr_used = false

simd_fp_exceptions = []

flags_written = []

semantic_legacy_128 = """
IF imm8[0] = 0:
    TEMP1 := SRC1.qword[0]
ELSE:
    TEMP1 := SRC1.qword[1]
IF imm8[4] = 0:
    TEMP2 := SRC2.qword[0]
ELSE:
    TEMP2 := SRC2.qword[1]
DEST[127:0] := PCLMUL128(TEMP1, TEMP2)
DEST[MAXVL-1:128] (Unmodified)
"""

semantic_vex_128 = """
IF imm8[0] = 0:
    TEMP1 := SRC1.qword[0]
ELSE:
    TEMP1 := SRC1.qword[1]
IF imm8[4] = 0:
    TEMP2 := SRC2.qword[0]
ELSE:
    TEMP2 := SRC2.qword[1]
DEST.xmm[0] := PCLMUL128(TEMP1, TEMP2)
DEST[MAXVL-1:128] := 0
"""

semantic_vex_256 = """
FOR i = 0 to 1:
    IF imm8[0] = 0:
        TEMP1 := SRC1.xmm[i].qword[0]
    ELSE:
        TEMP1 := SRC1.xmm[i].qword[1]
    IF imm8[4] = 0:
        TEMP2 := SRC2.xmm[i].qword[0]
    ELSE:
        TEMP2 := SRC2.xmm[i].qword[1]
    DEST.xmm[i] := PCLMUL128(TEMP1, TEMP2)
DEST[MAXVL-1:256] := 0
"""

semantic_evex = """
(KL, VL) = (1, 128), (2, 256), (4, 512)
FOR i = 0 to KL-1:
    IF writemask_enabled:
        IF imm8[0] = 0:
            TEMP1 := SRC1.xmm[i].qword[0]
        ELSE:
            TEMP1 := SRC1.xmm[i].qword[1]
        IF imm8[4] = 0:
            TEMP2 := SRC2.xmm[i].qword[0]
        ELSE:
            TEMP2 := SRC2.xmm[i].qword[1]
        DEST.xmm[i] := PCLMUL128(TEMP1, TEMP2)
    ELSE if zero_masking:
        DEST.xmm[i] := 0;
DEST[MAXVL-1:VL] := 0
"""

handler = "x86_pclmulqdq"
jit_lowering = "arm64_neon_pmul"
fallback = "zig_lane_loop"
