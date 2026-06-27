// ABSOLUTE/PABSW.inc
// ARM64/NEON translation mirror.
// Source contract: PABSW — Packed Absolute Value (Word).

semantic = """
PABSW: compute absolute value of each signed word element, storing unsigned result.
Category: simd_integer_absolute.
"""

source_isa = "arm64_neon"
target_isa = "x86"
x86_table = "ABSOLUTE/PABSW.inc"

name = "PABSW"
category = "simd_integer_absolute"
feature = "SSSE3"
element_type = "i16"
legacy_width = 128
lanes_128 = 8
lanes_256 = 16
lanes_512 = 32

encodings = [
  { opcode = "NP 0F 38 1D /r", form = "PABSW mm1, mm2/m64", op_en = "A", feature = "SSSE3" },
  { opcode = "66 0F 38 1D /r", form = "PABSW xmm1, xmm2/m128", op_en = "A", feature = "SSSE3" },
  { opcode = "VEX.128.66.0F38.WIG 1D /r", form = "VPABSW xmm1, xmm2/m128", op_en = "A", feature = "AVX" },
  { opcode = "VEX.256.66.0F38.WIG 1D /r", form = "VPABSW ymm1, ymm2/m256", op_en = "A", feature = "AVX2" },
  { opcode = "EVEX.128.66.0F38.WIG 1D /r", form = "VPABSW xmm1 {k1}{z}, xmm2/m128", op_en = "B", feature = "AVX512VL+AVX512BW" },
  { opcode = "EVEX.256.66.0F38.WIG 1D /r", form = "VPABSW ymm1 {k1}{z}, ymm2/m256", op_en = "B", feature = "AVX512VL+AVX512BW" },
  { opcode = "EVEX.512.66.0F38.WIG 1D /r", form = "VPABSW zmm1 {k1}{z}, zmm2/m512", op_en = "B", feature = "AVX512BW" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "ModRM:reg (w)", operand2 = "ModRM:r/m (r)", operand3 = "N/A", operand4 = "N/A" },
  { op_en = "B", tuple = "Full Mem", operand1 = "ModRM:reg (w)", operand2 = "ModRM:r/m (r)", operand3 = "N/A", operand4 = "N/A" }
]

semantic_legacy = """
for lane in 0..lanes:
    DEST.u16[lane] = abs(SRC.i16[lane]);
DEST[MAXVL-1:128] unchanged;
"""

semantic_vex_128 = """
for lane in 0..8:
    DEST.u16[lane] = abs(SRC.i16[lane]);
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
for lane in 0..16:
    DEST.u16[lane] = abs(SRC.i16[lane]);
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
(KL, VL) = (8, 128), (16, 256), (32, 512)
for j in 0..KL:
    if k1[j] or no_writemask:
        DEST.u16[j*16+15:j*16] = abs(SRC.i16[j*16+15:j*16]);
    else if merging:
        DEST.u16[j*16+15:j*16] unchanged;
    else:
        DEST.u16[j*16+15:j*16] = 0;
DEST[MAXVL-1:VL] = 0;
"""
