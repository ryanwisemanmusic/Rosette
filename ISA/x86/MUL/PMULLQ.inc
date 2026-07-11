// PMULLQ.inc

operand_encoding = [
  { op_en = "C", operand_1 = "ModRM:reg (w)", operand_2 = "EVEX.vvvv (r)", operand_3 = "ModRM:r/m (r)", operand_4 = "N/A" },
]

name = "VPMULLQ"
category = "simd_int_mul_low"
feature = "AVX512DQ"
element_type = "i64"

encodings = [
  { opcode = "EVEX.128.66.0F38.W1 40 /r", form = "VPMULLQ xmm1 {k1}{z}, xmm2, xmm3/m128/m64bcst", op_en = "C", feature = "AVX512DQ AVX512VL" },
  { opcode = "EVEX.256.66.0F38.W1 40 /r", form = "VPMULLQ ymm1 {k1}{z}, ymm2, ymm3/m256/m64bcst", op_en = "C", feature = "AVX512DQ AVX512VL" },
  { opcode = "EVEX.512.66.0F38.W1 40 /r", form = "VPMULLQ zmm1 {k1}{z}, zmm2, zmm3/m512/m64bcst", op_en = "C", feature = "AVX512DQ" },
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

semantic_evex = """
(KL, VL) = (2, 128), (4, 256), (8, 512)
FOR j := 0 TO KL-1
    i := j * 64
    IF writemask_enabled:
        IF broadcasting and SRC2 is memory:
            Temp[127:0] := SRC1.i64[j] * SRC2.i64[0]
        ELSE:
            Temp[127:0] := SRC1.i64[j] * SRC2.i64[j]
        DEST.i64[j] := Temp[63:0]
    ELSE if zero_masking:
        DEST.i64[j] = 0
DEST[MAXVL-1:VL] = 0
"""

handler = "x86_vpmullq"
jit_lowering = "arm64_neon_pmul_v2i64"
fallback = "zig_lane_loop"
