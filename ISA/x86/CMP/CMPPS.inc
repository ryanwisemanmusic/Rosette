jit_lowering = "arm64_documented_contract_cmpps"
// CMPPS.inc
// Compare packed single-precision floating-point values.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
CMPPS: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_float_compare.
"""

name = "CMPPS"
category = "simd_float_compare"
feature = "SSE"
element_type = "f32"
legacy_width = 128
lanes_128 = 4
lanes_256 = 8
lanes_512 = 16
mxcsr_used = true

encodings = [
  { opcode = "NP 0F C2 /r ib", form = "CMPPS xmm1, xmm2/m128, imm8", op_en = "A", feature = "SSE", imm = 8 },
  { opcode = "VEX.128.0F.WIG C2 /r ib", form = "VCMPPS xmm1, xmm2, xmm3/m128, imm8", op_en = "B", feature = "AVX", imm = 8 },
  { opcode = "VEX.256.0F.WIG C2 /r ib", form = "VCMPPS ymm1, ymm2, ymm3/m256, imm8", op_en = "B", feature = "AVX", imm = 8 },
  { opcode = "EVEX.128.0F.W0 C2 /r ib", form = "VCMPPS k1 {k2}, xmm2, xmm3/m128/m32bcst, imm8", op_en = "C", feature = "AVX512VL+AVX512F", imm = 8, writes_mask = true, read_mask_dest = false },
  { opcode = "EVEX.256.0F.W0 C2 /r ib", form = "VCMPPS k1 {k2}, ymm2, ymm3/m256/m32bcst, imm8", op_en = "C", feature = "AVX512VL+AVX512F", imm = 8, writes_mask = true, read_mask_dest = false },
  { opcode = "EVEX.512.0F.W0 C2 /r ib", form = "VCMPPS k1 {k2}, zmm2, zmm3/m512/m32bcst, imm8", op_en = "C", feature = "AVX512F", imm = 8, writes_mask = true, read_mask_dest = false }
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
for lane in 0..4:
    CMP = compare(DEST.f32[lane], SRC.f32[lane], predicate);
    if CMP is true:
        DEST.i32[lane] = -1;
    else:
        DEST.i32[lane] = 0;
DEST[MAXVL-1:128] unchanged;
"""

semantic_vex_128 = """
for lane in 0..4:
    CMP = compare(SRC1.f32[lane], SRC2.f32[lane], predicate);
    if CMP is true:
        DEST.i32[lane] = -1;
    else:
        DEST.i32[lane] = 0;
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
for lane in 0..8:
    CMP = compare(SRC1.f32[lane], SRC2.f32[lane], predicate);
    if CMP is true:
        DEST.i32[lane] = -1;
    else:
        DEST.i32[lane] = 0;
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
for each active f32 lane selected by k2 or no writemask:
    CMP = compare(SRC1.f32[lane], SRC2.f32[lane_or_broadcast], predicate);
    if CMP is true:
        DEST.bit[lane] = 1;
    else:
        DEST.bit[lane] = 0;
DEST[MAX_OPMASK_BITS-1:VL] = 0;
"""

simd_fp_exceptions = ["invalid", "denormal"]
