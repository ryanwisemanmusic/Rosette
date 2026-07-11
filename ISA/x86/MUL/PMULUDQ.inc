// PMULUDQ.inc

operand_encoding = [
  { op_en = "A", operand_1 = "ModRM:reg (r, w)", operand_2 = "ModRM:r/m (r)", operand_3 = "N/A", operand_4 = "N/A" },
  { op_en = "B", operand_1 = "ModRM:reg (w)", operand_2 = "VEX.vvvv (r)", operand_3 = "ModRM:r/m (r)", operand_4 = "N/A" },
  { op_en = "C", operand_1 = "ModRM:reg (w)", operand_2 = "EVEX.vvvv (r)", operand_3 = "ModRM:r/m (r)", operand_4 = "N/A" },
]

name = "PMULUDQ"
category = "simd_int_mul"
feature = "SSE2"
element_type = "u32"

encodings = [
  { opcode = "NP 0F F4 /r", form = "PMULUDQ mm1, mm2/m64", op_en = "A", feature = "SSE2" },
  { opcode = "66 0F F4 /r", form = "PMULUDQ xmm1, xmm2/m128", op_en = "A", feature = "SSE2" },
  { opcode = "VEX.128.66.0F.WIG F4 /r", form = "VPMULUDQ xmm1, xmm2, xmm3/m128", op_en = "B", feature = "AVX" },
  { opcode = "VEX.256.66.0F.WIG F4 /r", form = "VPMULUDQ ymm1, ymm2, ymm3/m256", op_en = "B", feature = "AVX2" },
  { opcode = "EVEX.128.66.0F.W1 F4 /r", form = "VPMULUDQ xmm1 {k1}{z}, xmm2, xmm3/m128/m64bcst", op_en = "C", feature = "AVX512F AVX512VL" },
  { opcode = "EVEX.256.66.0F.W1 F4 /r", form = "VPMULUDQ ymm1 {k1}{z}, ymm2, ymm3/m256/m64bcst", op_en = "C", feature = "AVX512F AVX512VL" },
  { opcode = "EVEX.512.66.0F.W1 F4 /r", form = "VPMULUDQ zmm1 {k1}{z}, zmm2, zmm3/m512/m64bcst", op_en = "C", feature = "AVX512F" },
]

element_size = 32
lane_type = "doubleword"

lanes = {
  mmx = 2,
  xmm = 4,
  ymm = 8,
  zmm = 16
}

mxcsr_used = false

simd_fp_exceptions = []

flags_written = []

semantic_legacy_128 = """
DEST.u64[0] = DEST.u32[0] * SRC.u32[0];
DEST.u64[1] = DEST.u32[2] * SRC.u32[2];
DEST[MAXVL-1:128] unchanged;
"""

semantic_vex_128 = """
DEST.u64[0] = SRC1.u32[0] * SRC2.u32[0];
DEST.u64[1] = SRC1.u32[2] * SRC2.u32[2];
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
DEST.u64[0] = SRC1.u32[0] * SRC2.u32[0];
DEST.u64[1] = SRC1.u32[2] * SRC2.u32[2];
DEST.u64[2] = SRC1.u32[4] * SRC2.u32[4];
DEST.u64[3] = SRC1.u32[6] * SRC2.u32[6];
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
(KL, VL) = (2, 128), (4, 256), (8, 512)
FOR j := 0 TO KL-1
    i := j * 64
    IF writemask_enabled:
        IF broadcasting and SRC2 is memory:
            DEST.u64[j] := ZeroExtend64(SRC1.u32[i/2]) * ZeroExtend64(SRC2.u32[0])
        ELSE:
            DEST.u64[j] := ZeroExtend64(SRC1.u32[i/2]) * ZeroExtend64(SRC2.u32[i/2])
    ELSE if zero_masking:
        DEST.u64[j] = 0
DEST[MAXVL-1:VL] = 0
"""

handler = "x86_pmuludq"
jit_lowering = "arm64_neon_umull_v2i32"
fallback = "zig_lane_loop"
