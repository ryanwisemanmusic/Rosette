// CMP/VPCMPUB.inc
// Compare Packed Unsigned Byte Values Into Mask.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VPCMPUB: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_integer_compare_mask.
"""

name = "VPCMPUB"
category = "compare"
feature = "AVX512BW"
element_type = "u8"
lanes_128 = 16
lanes_256 = 32
lanes_512 = 64

encodings = [
  { opcode = "EVEX.128.66.0F3A.W0 3E /r ib", form = "VPCMPUB k1 {k2}, xmm2, xmm3/m128, imm8", op_en = "A", feature = "AVX512VL+AVX512BW", vector_length = 128, encoding = "evex", writes_mask = true, read_mask_dest = false, imm = 8 },
  { opcode = "EVEX.256.66.0F3A.W0 3E /r ib", form = "VPCMPUB k1 {k2}, ymm2, ymm3/m256, imm8", op_en = "A", feature = "AVX512VL+AVX512BW", vector_length = 256, encoding = "evex", writes_mask = true, read_mask_dest = false, imm = 8 },
  { opcode = "EVEX.512.66.0F3A.W0 3E /r ib", form = "VPCMPUB k1 {k2}, zmm2, zmm3/m512, imm8", op_en = "A", feature = "AVX512BW", vector_length = 512, encoding = "evex", writes_mask = true, read_mask_dest = false, imm = 8 }
]

operand_encodings = [
  { op_en = "A", tuple = "Full", operand1 = "ModRM:reg (w, opmask)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "imm8" }
]

predicate_table = [
  { value = 0, name = "EQ", description = "equal" },
  { value = 1, name = "LT", description = "less-than (unsigned)" },
  { value = 2, name = "LE", description = "less-than-or-equal (unsigned)" },
  { value = 3, name = "FALSE", description = "false (always 0)" },
  { value = 4, name = "NEQ", description = "not-equal" },
  { value = 5, name = "NLT", description = "not-less-than (unsigned)" },
  { value = 6, name = "NLE", description = "not-less-than-or-equal (unsigned)" },
  { value = 7, name = "TRUE", description = "true (always 1)" },
]

semantic_evex = """
(KL, VL) = (16, 128), (32, 256), (64, 512);
for each active byte lane selected by k2 or no writemask:
    CMP = unsigned_compare(SRC1.u8[lane], SRC2.u8[lane], predicate);
    if CMP is true:
        DEST.bit[lane] = 1;
    else:
        DEST.bit[lane] = 0;
DEST[MAX_OPMASK_BITS-1:VL] = 0;
"""

flags_written = []
simd_fp_exceptions = []
