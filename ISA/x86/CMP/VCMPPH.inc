// CMP/VCMPPH.inc
// Compare Packed FP16 Values.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VCMPPH: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_float_compare.
"""

name = "VCMPPH"
category = "compare"
feature = "AVX512-FP16"
element_type = "f16"
scalar = false
lanes_128 = 8
lanes_256 = 16
lanes_512 = 32

encodings = [
  { opcode = "EVEX.128.NP.0F3A.W0 C2 /r ib", form = "VCMPPH k1 {k2}, xmm2, xmm3/m128, imm8", op_en = "A", feature = "AVX512-FP16", vector_length = 128, encoding = "evex", writes_mask = true, read_mask_dest = false, imm = 8 },
  { opcode = "EVEX.256.NP.0F3A.W0 C2 /r ib", form = "VCMPPH k1 {k2}, ymm2, ymm3/m256, imm8", op_en = "A", feature = "AVX512-FP16", vector_length = 256, encoding = "evex", writes_mask = true, read_mask_dest = false, imm = 8 },
  { opcode = "EVEX.512.NP.0F3A.W0 C2 /r ib", form = "VCMPPH k1 {k2}, zmm2, zmm3/m512, imm8", op_en = "A", feature = "AVX512-FP16", vector_length = 512, encoding = "evex", writes_mask = true, read_mask_dest = false, imm = 8 }
]

operand_encodings = [
  { op_en = "A", tuple = "Full", operand1 = "ModRM:reg (w, opmask)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "imm8" }
]

predicate_table = [
  { value = 0, name = "EQ", description = "equal (ordered, non-signaling)" },
  { value = 1, name = "LT", description = "less-than (ordered, signaling)" },
  { value = 2, name = "LE", description = "less-than-or-equal (ordered, signaling)" },
  { value = 3, name = "UNORD", description = "unordered (non-signaling)" },
  { value = 4, name = "NEQ", description = "not-equal (unordered, non-signaling)" },
  { value = 5, name = "NLT", description = "not-less-than (unordered, signaling)" },
  { value = 6, name = "NLE", description = "not-less-than-or-equal (unordered, signaling)" },
  { value = 7, name = "ORD", description = "ordered (non-signaling)" },
]
extended_predicates = "24 additional predicates (values 8-31) via imm8[3]=1"

semantic_evex = """
(KL, VL) = (8, 128), (16, 256), (32, 512);
for each active f16 lane selected by k2 or no writemask:
    CMP = compare(SRC1.f16[lane], SRC2.f16[lane], predicate);
    if CMP is true:
        DEST.bit[lane] = 1;
    else:
        DEST.bit[lane] = 0;
DEST[MAX_OPMASK_BITS-1:VL] = 0;
"""

simd_fp_exceptions = ["Invalid", "Denormal"]
flags_written = []
