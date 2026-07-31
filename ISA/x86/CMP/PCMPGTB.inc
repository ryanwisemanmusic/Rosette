jit_lowering = "arm64_documented_contract_pcmpgtb"
// CMP/PCMPGTB.inc
// Compare Packed Signed Bytes for Greater Than.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
PCMPGTB: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_integer_compare.
"""

name = "PCMPGTB"
category = "compare"
feature = "MMX"
element_type = "i8"
legacy_width = 64
lanes_64 = 8
lanes_128 = 16
lanes_256 = 32
lanes_512 = 64

encodings = [
  { opcode = "NP 0F 64 /r", form = "PCMPGTB mm, mm/m64", op_en = "A", feature = "MMX", vector_length = 64, encoding = "legacy" },
  { opcode = "66 0F 64 /r", form = "PCMPGTB xmm1, xmm2/m128", op_en = "A", feature = "SSE2", vector_length = 128, encoding = "legacy" },
  { opcode = "VEX.128.66.0F.WIG 64 /r", form = "VPCMPGTB xmm1, xmm2, xmm3/m128", op_en = "B", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F.WIG 64 /r", form = "VPCMPGTB ymm1, ymm2, ymm3/m256", op_en = "B", feature = "AVX2", vector_length = 256, encoding = "vex" },
  { opcode = "EVEX.128.66.0F.WIG 64 /r", form = "VPCMPGTB xmm1 {k1}{z}, xmm2, xmm3/m128", op_en = "C", feature = "AVX512VL+AVX512BW", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F.WIG 64 /r", form = "VPCMPGTB ymm1 {k1}{z}, ymm2, ymm3/m256", op_en = "C", feature = "AVX512VL+AVX512BW", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F.WIG 64 /r", form = "VPCMPGTB zmm1 {k1}{z}, zmm2, zmm3/m512", op_en = "C", feature = "AVX512BW", vector_length = 512, encoding = "evex" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "ModRM:reg (r, w)", operand2 = "ModRM:r/m (r)", operand3 = "N/A", operand4 = "N/A" },
  { op_en = "B", tuple = "N/A", operand1 = "ModRM:reg (w)", operand2 = "VEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "N/A" },
  { op_en = "C", tuple = "Full", operand1 = "ModRM:reg (w, opmask)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "N/A" }
]

semantic_legacy_64 = """
for byte in 0..8:
    if DEST.i8[byte] > SRC.i8[byte]:     # signed greater-than
        DEST.i8[byte] = -1;
    else:
        DEST.i8[byte] = 0;
"""

semantic_legacy_128 = """
for byte in 0..16:
    if DEST.i8[byte] > SRC.i8[byte]:     # signed greater-than
        DEST.i8[byte] = -1;
    else:
        DEST.i8[byte] = 0;
DEST[MAXVL-1:128] unchanged;
"""

semantic_vex_128 = """
for byte in 0..16:
    if SRC1.i8[byte] > SRC2.i8[byte]:   # signed greater-than
        DEST.i8[byte] = -1;
    else:
        DEST.i8[byte] = 0;
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
for byte in 0..32:
    if SRC1.i8[byte] > SRC2.i8[byte]:   # signed greater-than
        DEST.i8[byte] = -1;
    else:
        DEST.i8[byte] = 0;
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
(KL, VL) = (16, 128), (32, 256), (64, 512);
for each active byte lane selected by k2 or no writemask:
    if SRC1.i8[lane] > SRC2.i8[lane]:   # signed greater-than
        DEST.i8[lane] = -1;
    else:
        DEST.i8[lane] = 0;
DEST[MAXVL-1:VL] = 0;
"""

flags_written = []
simd_fp_exceptions = []
