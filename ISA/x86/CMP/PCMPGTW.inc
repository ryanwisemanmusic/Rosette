jit_lowering = "arm64_documented_contract_pcmpgtw"
// CMP/PCMPGTW.inc
// Compare Packed Signed Words for Greater Than.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
PCMPGTW: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_integer_compare.
"""

name = "PCMPGTW"
category = "compare"
feature = "MMX"
element_type = "i16"
legacy_width = 64
lanes_64 = 4
lanes_128 = 8
lanes_256 = 16
lanes_512 = 32

encodings = [
  { opcode = "NP 0F 65 /r", form = "PCMPGTW mm, mm/m64", op_en = "A", feature = "MMX", vector_length = 64, encoding = "legacy" },
  { opcode = "66 0F 65 /r", form = "PCMPGTW xmm1, xmm2/m128", op_en = "A", feature = "SSE2", vector_length = 128, encoding = "legacy" },
  { opcode = "VEX.128.66.0F.WIG 65 /r", form = "VPCMPGTW xmm1, xmm2, xmm3/m128", op_en = "B", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F.WIG 65 /r", form = "VPCMPGTW ymm1, ymm2, ymm3/m256", op_en = "B", feature = "AVX2", vector_length = 256, encoding = "vex" },
  { opcode = "EVEX.128.66.0F.WIG 65 /r", form = "VPCMPGTW xmm1 {k1}{z}, xmm2, xmm3/m128", op_en = "C", feature = "AVX512VL+AVX512BW", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F.WIG 65 /r", form = "VPCMPGTW ymm1 {k1}{z}, ymm2, ymm3/m256", op_en = "C", feature = "AVX512VL+AVX512BW", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F.WIG 65 /r", form = "VPCMPGTW zmm1 {k1}{z}, zmm2, zmm3/m512", op_en = "C", feature = "AVX512BW", vector_length = 512, encoding = "evex" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "ModRM:reg (r, w)", operand2 = "ModRM:r/m (r)", operand3 = "N/A", operand4 = "N/A" },
  { op_en = "B", tuple = "N/A", operand1 = "ModRM:reg (w)", operand2 = "VEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "N/A" },
  { op_en = "C", tuple = "Full", operand1 = "ModRM:reg (w, opmask)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "N/A" }
]

semantic_legacy_64 = """
for word in 0..4:
    if DEST.i16[word] > SRC.i16[word]:     # signed greater-than
        DEST.i16[word] = -1;
    else:
        DEST.i16[word] = 0;
"""

semantic_legacy_128 = """
for word in 0..8:
    if DEST.i16[word] > SRC.i16[word]:     # signed greater-than
        DEST.i16[word] = -1;
    else:
        DEST.i16[word] = 0;
DEST[MAXVL-1:128] unchanged;
"""

semantic_vex_128 = """
for word in 0..8:
    if SRC1.i16[word] > SRC2.i16[word]:   # signed greater-than
        DEST.i16[word] = -1;
    else:
        DEST.i16[word] = 0;
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
for word in 0..16:
    if SRC1.i16[word] > SRC2.i16[word]:   # signed greater-than
        DEST.i16[word] = -1;
    else:
        DEST.i16[word] = 0;
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
(KL, VL) = (8, 128), (16, 256), (32, 512);
for each active word lane selected by k2 or no writemask:
    if SRC1.i16[lane] > SRC2.i16[lane]:   # signed greater-than
        DEST.i16[lane] = -1;
    else:
        DEST.i16[lane] = 0;
DEST[MAXVL-1:VL] = 0;
"""

flags_written = []
simd_fp_exceptions = []
