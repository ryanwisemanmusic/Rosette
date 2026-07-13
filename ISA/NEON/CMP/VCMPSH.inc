// CMP/VCMPSH.inc
// ARM64/NEON translation mirror generated from ISA/x86/CMP/VCMPSH.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VCMPSH: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_scalar_float_compare.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CMP/VCMPSH.inc"
x86_handler = "x86_vcmpsh"
neon_lowering = "arm64_documented_contract_vcmpsh"
lowering_kind = "neon_scalar"

name = "VCMPSH"
aliases = []
category = "simd_scalar_float_compare"
feature = "AVX512-FP16"
element_type = "f16"
element_size = 16

encodings = [
  { opcode = "EVEX.LLIG.F3.0F3A.W0 C2 /r ib", form = "VCMPSH k1 {k2}, xmm2, xmm3/m16, imm8", op_en = "A", feature = "AVX512-FP16", vector_length = 0, encoding = "evex", writes_mask = true, read_mask_dest = false, imm = 8 }
]

operand_encoding = {
  A = ["ModRM:reg (w, opmask)", "EVEX.vvvv (r)", "ModRM:r/m (r)", "imm8 (r)"]
}

active_lane = 0
lane_type = "scalar_half_precision"

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
    "EQ" = "CMPEQSH",
    "LT" = "CMPLTSH",
    "LE" = "CMPLESH",
    "UNORD" = "CMPUNORDSH",
    "NEQ" = "CMPNEQSH",
    "NLT" = "CMPNLTSH",
    "NLE" = "CMPNLESH",
    "ORD" = "CMPORDSH"
  }
}

semantic_evex_scalar = """
CMP = compare(SRC1.f16[0], SRC2.f16[0], predicate);
if CMP is true:
    DEST.bit[0] = 1;
else:
    DEST.bit[0] = 0;
DEST[MAX_OPMASK_BITS-1:1] = 0;
"""

handler = "x86_vcmpsh"
jit_lowering = "arm64_documented_contract_vcmpsh"
fallback = "zig_scalar_fcmp_h"

neon_register_model = """
x86 scalar FP16 lane (xmm[15:0]) is mapped onto an ARM64 h-register; the comparison result is written to an opmask register.
"""

neon_flag_model = """
No x86 flags are modified; MXCSR invalid/denormal exception status is preserved through Rosette SIMD floating-point side-effect handlers.
"""

neon_assembly = """
// ARM64 NEON provides FCMEQ, FCMLT, FCMGT for half-precision comparisons.
// Example for EQ predicate:
//     fcmeq hD, hN, hM
//     bl rosette_apply_mxcsr_float_exceptions
// For signalling predicates, the lowering raises #XM on SNaN inputs.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, writemask, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
