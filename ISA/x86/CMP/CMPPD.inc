jit_lowering = "arm64_documented_contract_cmppd"
// CMPPD.inc
// Compare packed double-precision floating-point values.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
CMPPD: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_float_compare.
"""

name = "CMPPD"
category = "simd_float_compare"
feature = "SSE2"
element_type = "f64"
legacy_width = 128
lanes_128 = 2
lanes_256 = 4
lanes_512 = 8
mxcsr_used = true

encodings = [
  { opcode = "66 0F C2 /r ib", form = "CMPPD xmm1, xmm2/m128, imm8", op_en = "A", feature = "SSE2", imm = 8 },
  { opcode = "VEX.128.66.0F.WIG C2 /r ib", form = "VCMPPD xmm1, xmm2, xmm3/m128, imm8", op_en = "B", feature = "AVX", imm = 8 },
  { opcode = "VEX.256.66.0F.WIG C2 /r ib", form = "VCMPPD ymm1, ymm2, ymm3/m256, imm8", op_en = "B", feature = "AVX", imm = 8 },
  { opcode = "EVEX.128.66.0F.W1 C2 /r ib", form = "VCMPPD k1 {k2}, xmm2, xmm3/m128/m64bcst, imm8", op_en = "C", feature = "AVX512VL+AVX512F", imm = 8, writes_mask = true, read_mask_dest = false },
  { opcode = "EVEX.256.66.0F.W1 C2 /r ib", form = "VCMPPD k1 {k2}, ymm2, ymm3/m256/m64bcst, imm8", op_en = "C", feature = "AVX512VL+AVX512F", imm = 8, writes_mask = true, read_mask_dest = false },
  { opcode = "EVEX.512.66.0F.W1 C2 /r ib", form = "VCMPPD k1 {k2}, zmm2, zmm3/m512/m64bcst, imm8", op_en = "C", feature = "AVX512F", imm = 8, writes_mask = true, read_mask_dest = false }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "ModRM:reg (r, w)", operand2 = "ModRM:r/m (r)", operand3 = "N/A", operand4 = "N/A" },
  { op_en = "B", tuple = "N/A", operand1 = "ModRM:reg (w)", operand2 = "VEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "N/A" },
  { op_en = "C", tuple = "Full", operand1 = "ModRM:reg (w, opmask)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "imm8" }
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
extended_predicates = "24 additional predicates (values 8-31) via imm8[3]=1 with VEX/EVEX prefixes"

semantic_legacy = """
for lane in 0..2:
    CMP = compare(DEST.f64[lane], SRC.f64[lane], predicate);
    if CMP is true:
        DEST.i64[lane] = -1;
    else:
        DEST.i64[lane] = 0;
DEST[MAXVL-1:128] unchanged;
"""

semantic_vex_128 = """
for lane in 0..2:
    CMP = compare(SRC1.f64[lane], SRC2.f64[lane], predicate);
    if CMP is true:
        DEST.i64[lane] = -1;
    else:
        DEST.i64[lane] = 0;
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
for lane in 0..4:
    CMP = compare(SRC1.f64[lane], SRC2.f64[lane], predicate);
    if CMP is true:
        DEST.i64[lane] = -1;
    else:
        DEST.i64[lane] = 0;
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
for each active f64 lane selected by k2 or no writemask:
    CMP = compare(SRC1.f64[lane], SRC2.f64[lane_or_broadcast], predicate);
    if CMP is true:
        DEST.bit[lane] = 1;
    else:
        DEST.bit[lane] = 0;
DEST[MAX_OPMASK_BITS-1:VL] = 0;
"""

simd_fp_exceptions = ["invalid", "denormal"]
