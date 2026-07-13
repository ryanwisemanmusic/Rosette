// CMP/VPCMPUQ.inc
// ARM64/NEON translation mirror generated from ISA/x86/CMP/VPCMPUQ.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VPCMPUQ: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_integer_compare.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CMP/VPCMPUQ.inc"
x86_handler = "x86_vpcmpuq"
neon_lowering = "arm64_documented_contract_vpcmpuq"
lowering_kind = "neon_mask_vector"

name = "VPCMPUQ"
aliases = []
category = "simd_integer_compare"
feature = "AVX512F"
element_type = "u64"
element_size = 64

encodings = [
  { opcode = "EVEX.128.66.0F3A.W1 1E /r ib", form = "VPCMPUQ k1 {k2}, xmm2, xmm3/m128/m64bcst, imm8", op_en = "A", feature = "AVX512VL+AVX512F", vector_length = 128, encoding = "evex", writes_mask = true, read_mask_dest = false, imm = 8, broadcast = "m64bcst" },
  { opcode = "EVEX.256.66.0F3A.W1 1E /r ib", form = "VPCMPUQ k1 {k2}, ymm2, ymm3/m256/m64bcst, imm8", op_en = "A", feature = "AVX512VL+AVX512F", vector_length = 256, encoding = "evex", writes_mask = true, read_mask_dest = false, imm = 8, broadcast = "m64bcst" },
  { opcode = "EVEX.512.66.0F3A.W1 1E /r ib", form = "VPCMPUQ k1 {k2}, zmm2, zmm3/m512/m64bcst, imm8", op_en = "A", feature = "AVX512F", vector_length = 512, encoding = "evex", writes_mask = true, read_mask_dest = false, imm = 8, broadcast = "m64bcst" }
]

operand_encoding = {
  A = ["ModRM:reg (w, opmask)", "EVEX.vvvv (r)", "ModRM:r/m (r)", "imm8 (r)"]
}

lanes = { xmm = 2, ymm = 4, zmm = 8 }
flags_written = []
mxcsr_used = false

simd_fp_exceptions = []

comparison_predicate = {
  imm8_range = "0..7",
  predicates = {
    0 = "EQ (equal)",
    1 = "LT (less-than, unsigned)",
    2 = "LE (less-than-or-equal, unsigned)",
    3 = "FALSE (always 0)",
    4 = "NEQ (not-equal)",
    5 = "NLT (not-less-than, unsigned)",
    6 = "NLE (not-less-than-or-equal, unsigned)",
    7 = "TRUE (always 1)"
  }
}

semantic_evex = """
(KL, VL) = (2, 128), (4, 256), (8, 512);
for each active qword lane selected by k2 or no writemask:
    if broadcasting and SRC2 is memory:
        CMP = unsigned_compare(SRC1.u64[lane], SRC2.u64[0], predicate);
    else:
        CMP = unsigned_compare(SRC1.u64[lane], SRC2.u64[lane], predicate);
    if CMP is true:
        DEST.bit[lane] = 1;
    else:
        DEST.bit[lane] = 0;
DEST[MAX_OPMASK_BITS-1:VL] = 0;
"""

handler = "x86_vpcmpuq"
jit_lowering = "arm64_documented_contract_vpcmpuq"
fallback = "zig_mask_loop_icmp_uq"

neon_register_model = """
x86 XMM/YMM/ZMM qword lanes are compared unsigned via ARM64 vector instructions; result packed into an opmask register.
"""

neon_flag_model = """
No x86 flags are modified; no MXCSR side-effects occur.
"""

neon_assembly = """
// VPCMPUQ: unsigned qword comparison with predicate to opmask.
// ARM64: CMHI/CMHS/CMEQ for unsigned 64-bit lanes.
// For predicate 1 (LT): cmhi vT.2d, vM.2d, vN.2d (unsigned, swapped)
// For predicate 2 (LE): cmhs vT.2d, vM.2d, vN.2d (unsigned, swapped)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, writemask, broadcast, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
