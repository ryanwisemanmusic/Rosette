// ABSOLUTE/PABSQ.inc
// ARM64/NEON translation mirror.
// Source contract: PABSQ — Packed Absolute Value (Qword).

semantic = """
PABSQ: compute absolute value of each signed qword element, storing unsigned result.
Category: simd_integer_absolute.
"""

source_isa = "arm64_neon"
target_isa = "x86"
x86_table = "ABSOLUTE/PABSQ.inc"

name = "PABSQ"
category = "simd_integer_absolute"
feature = "AVX512F"
element_type = "i64"
legacy_width = 128
lanes_128 = 2
lanes_256 = 4
lanes_512 = 8

encodings = [
  { opcode = "EVEX.128.66.0F38.W1 1F /r", form = "VPABSQ xmm1 {k1}{z}, xmm2/m128/m64bcst", op_en = "B", feature = "AVX512VL+AVX512F" },
  { opcode = "EVEX.256.66.0F38.W1 1F /r", form = "VPABSQ ymm1 {k1}{z}, ymm2/m256/m64bcst", op_en = "B", feature = "AVX512VL+AVX512F" },
  { opcode = "EVEX.512.66.0F38.W1 1F /r", form = "VPABSQ zmm1 {k1}{z}, zmm2/m512/m64bcst", op_en = "B", feature = "AVX512F" }
]

operand_encodings = [
  { op_en = "B", tuple = "Full Mem", operand1 = "ModRM:reg (w)", operand2 = "ModRM:r/m (r)", operand3 = "N/A", operand4 = "N/A" }
]

semantic_evex = """
(KL, VL) = (2, 128), (4, 256), (8, 512)
for j in 0..KL:
    if k1[j] or no_writemask:
        DEST.u64[j*64+63:j*64] = abs(SRC.i64[j*64+63:j*64]);
    else if merging:
        DEST.u64[j*64+63:j*64] unchanged;
    else:
        DEST.u64[j*64+63:j*64] = 0;
DEST[MAXVL-1:VL] = 0;
"""
