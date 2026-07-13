// CMP/PCMPGTQ.inc
// Compare Packed Signed Qwords for Greater Than.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
PCMPGTQ: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_integer_compare.
"""

name = "PCMPGTQ"
category = "compare"
feature = "SSE4_2"
element_type = "i64"
legacy_width = 128
lanes_128 = 2
lanes_256 = 4
lanes_512 = 8

encodings = [
  { opcode = "66 0F 38 37 /r", form = "PCMPGTQ xmm1, xmm2/m128", op_en = "A", feature = "SSE4_2", vector_length = 128, encoding = "legacy" },
  { opcode = "VEX.128.66.0F38.WIG 37 /r", form = "VPCMPGTQ xmm1, xmm2, xmm3/m128", op_en = "B", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F38.WIG 37 /r", form = "VPCMPGTQ ymm1, ymm2, ymm3/m256", op_en = "B", feature = "AVX2", vector_length = 256, encoding = "vex" },
  { opcode = "EVEX.128.66.0F38.W1 37 /r", form = "VPCMPGTQ xmm1 {k1}{z}, xmm2, xmm3/m128/m64bcst", op_en = "C", feature = "AVX512VL+AVX512F", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F38.W1 37 /r", form = "VPCMPGTQ ymm1 {k1}{z}, ymm2, ymm3/m256/m64bcst", op_en = "C", feature = "AVX512VL+AVX512F", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F38.W1 37 /r", form = "VPCMPGTQ zmm1 {k1}{z}, zmm2, zmm3/m512/m64bcst", op_en = "C", feature = "AVX512F", vector_length = 512, encoding = "evex" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "ModRM:reg (r, w)", operand2 = "ModRM:r/m (r)", operand3 = "N/A", operand4 = "N/A" },
  { op_en = "B", tuple = "N/A", operand1 = "ModRM:reg (w)", operand2 = "VEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "N/A" },
  { op_en = "C", tuple = "Full", operand1 = "ModRM:reg (w, opmask)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "N/A" }
]

semantic_legacy_128 = """
for qword in 0..2:
    if DEST.i64[qword] > SRC.i64[qword]:     # signed greater-than
        DEST.i64[qword] = -1;
    else:
        DEST.i64[qword] = 0;
DEST[MAXVL-1:128] unchanged;
"""

semantic_vex_128 = """
for qword in 0..2:
    if SRC1.i64[qword] > SRC2.i64[qword]:   # signed greater-than
        DEST.i64[qword] = -1;
    else:
        DEST.i64[qword] = 0;
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
for qword in 0..4:
    if SRC1.i64[qword] > SRC2.i64[qword]:   # signed greater-than
        DEST.i64[qword] = -1;
    else:
        DEST.i64[qword] = 0;
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
(KL, VL) = (2, 128), (4, 256), (8, 512);
for each active qword lane selected by k2 or no writemask:
    if SRC1.i64[lane] > SRC2.i64[lane_or_broadcast]:   # signed greater-than
        DEST.i64[lane] = -1;
    else:
        DEST.i64[lane] = 0;
DEST[MAXVL-1:VL] = 0;
"""

flags_written = []
simd_fp_exceptions = []
