// CMP/VCMPPH.inc
// ARM64/NEON translation mirror generated from ISA/x86/CMP/VCMPPH.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VCMPPH: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_float_compare.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CMP/VCMPPH.inc"
x86_handler = "x86_vcmpph"
neon_lowering = "arm64_documented_contract_vcmpph"
lowering_kind = "neon_vector"

name = "VCMPPH"
aliases = []
category = "simd_float_compare"
feature = "AVX512-FP16"
element_type = "f16"
element_size = 16

encodings = [
  { opcode = "EVEX.128.NP.0F3A.W0 C2 /r ib", form = "VCMPPH k1 {k2}, xmm2, xmm3/m128, imm8", op_en = "A", feature = "AVX512-FP16", vector_length = 128, encoding = "evex", writes_mask = true, read_mask_dest = false, imm = 8 },
  { opcode = "EVEX.256.NP.0F3A.W0 C2 /r ib", form = "VCMPPH k1 {k2}, ymm2, ymm3/m256, imm8", op_en = "A", feature = "AVX512-FP16", vector_length = 256, encoding = "evex", writes_mask = true, read_mask_dest = false, imm = 8 },
  { opcode = "EVEX.512.NP.0F3A.W0 C2 /r ib", form = "VCMPPH k1 {k2}, zmm2, zmm3/m512, imm8", op_en = "A", feature = "AVX512-FP16", vector_length = 512, encoding = "evex", writes_mask = true, read_mask_dest = false, imm = 8 }
]

operand_encoding = {
  A = ["ModRM:reg (w, opmask)", "EVEX.vvvv (r)", "ModRM:r/m (r)", "imm8 (r)"]
}

lanes = { xmm = 8, ymm = 16, zmm = 32 }
flags_written = []
mxcsr_used = true

simd_fp_exceptions = ["Invalid", "Denormal"]

comparison_predicate = {
  imm8_range = "0..7",
  predicates = {
    0 = "EQ (equal)",
    1 = "LT (less-than)",
    2 = "LE (less-than-or-equal)",
    3 = "UNORD (unordered)",
    4 = "NEQ (not-equal)",
    5 = "NLT (not-less-than)",
    6 = "NLE (not-less-than-or-equal)",
    7 = "ORD (ordered)"
  },
  mnemonic_predicates = {
    "EQ" = "CMPEQPH",
    "LT" = "CMPLTPH",
    "LE" = "CMPLEPH",
    "UNORD" = "CMPUNORDPH",
    "NEQ" = "CMPNEQPH",
    "NLT" = "CMPNLTPH",
    "NLE" = "CMPNLEPH",
    "ORD" = "CMPORDPH"
  }
}

semantic_evex_128 = """
(KL, VL) = (8, 128);
for each active f16 lane selected by k2 or no writemask:
    CMP = compare(SRC1.f16[lane], SRC2.f16[lane], predicate);
    if CMP is true:
        DEST.bit[lane] = 1;
    else:
        DEST.bit[lane] = 0;
DEST[MAX_OPMASK_BITS-1:VL] = 0;
"""

semantic_evex_256 = """
(KL, VL) = (16, 256);
for each active f16 lane selected by k2 or no writemask:
    CMP = compare(SRC1.f16[lane], SRC2.f16[lane], predicate);
    if CMP is true:
        DEST.bit[lane] = 1;
    else:
        DEST.bit[lane] = 0;
DEST[MAX_OPMASK_BITS-1:VL] = 0;
"""

semantic_evex_512 = """
(KL, VL) = (32, 512);
for each active f16 lane selected by k2 or no writemask:
    CMP = compare(SRC1.f16[lane], SRC2.f16[lane], predicate);
    if CMP is true:
        DEST.bit[lane] = 1;
    else:
        DEST.bit[lane] = 0;
DEST[MAX_OPMASK_BITS-1:VL] = 0;
"""

handler = "x86_vcmpph"
jit_lowering = "arm64_documented_contract_vcmpph"
fallback = "zig_lane_loop_fcmp_ph"

neon_register_model = """
x86 xmm/ymm/zmm FP16 lanes are mapped onto ARM64 v registers; the comparison produces a mask register result per lane.
"""

neon_flag_model = """
No x86 flags are modified; MXCSR invalid/denormal exception status is preserved through Rosette SIMD floating-point side-effect handlers.
"""

neon_assembly = """
// ARM64 NEON provides FCMEQ, FCMLT, FCMGT for half-precision comparisons.
// Example for EQ predicate:
//     fcmeq vD.8h, vN.8h, vM.8h
// For signalling predicates (#XM on SNaN), the ARM64 lowering must raise the
// appropriate SIMD floating-point exception through Rosette MXCSR handlers.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, writemask, broadcast, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
