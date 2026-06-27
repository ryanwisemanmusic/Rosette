// ABSOLUTE/VDBPSADBW.inc
// ARM64/NEON translation mirror.
// Source contract: VDBPSADBW — Double Block Packed Sum-Absolute-Differences on Unsigned Bytes.

semantic = """
VDBPSADBW: within 128-bit lanes, shuffle dword elements from SRC2 using imm8, then compute sum of absolute differences between quadword superblocks.
Category: simd_integer_sad.
"""

source_isa = "arm64_neon"
target_isa = "x86"
x86_table = "ABSOLUTE/VDBPSADBW.inc"

name = "VDBPSADBW"
category = "simd_integer_sad"
feature = "AVX512BW"
element_type = "u8"
legacy_width = 128
lanes_128 = 8
lanes_256 = 16
lanes_512 = 32

encodings = [
  { opcode = "EVEX.128.66.0F3A.W0 42 /r ib", form = "VDBPSADBW xmm1 {k1}{z}, xmm2, xmm3/m128, imm8", op_en = "A", feature = "AVX512VL+AVX512BW", imm = 8 },
  { opcode = "EVEX.256.66.0F3A.W0 42 /r ib", form = "VDBPSADBW ymm1 {k1}{z}, ymm2, ymm3/m256, imm8", op_en = "A", feature = "AVX512VL+AVX512BW", imm = 8 },
  { opcode = "EVEX.512.66.0F3A.W0 42 /r ib", form = "VDBPSADBW zmm1 {k1}{z}, zmm2, zmm3/m512, imm8", op_en = "A", feature = "AVX512BW", imm = 8 }
]

operand_encodings = [
  { op_en = "A", tuple = "Full Mem", operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "imm8" }
]

semantic_evex = """
(KL, VL) = (8, 128), (16, 256), (32, 512)
For each 128-bit lane I:
    TMP1[I+31:I] = select(SRC2[I+127:I], imm8[1:0])
    TMP1[I+63:I+32] = select(SRC2[I+127:I], imm8[3:2])
    TMP1[I+95:I+64] = select(SRC2[I+127:I], imm8[5:4])
    TMP1[I+127:I+96] = select(SRC2[I+127:I], imm8[7:6])
For each 64-bit superblock offset I:
    TMP_DEST[I+15:I] = sum(abs(SRC1[I+7:I] - TMP1[I+7:I]), ...)
    TMP_DEST[I+31:I+16] = sum(abs(SRC1[I+7:I] - TMP1[I+15:I+8]), ...)
    TMP_DEST[I+47:I+32] = sum(abs(SRC1[I+39:I+32] - TMP1[I+23:I+16]), ...)
    TMP_DEST[I+63:I+48] = sum(abs(SRC1[I+39:I+32] - TMP1[I+31:I+24]), ...)
Apply writemask k1 at 16-bit granularity;
DEST[MAXVL-1:VL] = 0;
"""
