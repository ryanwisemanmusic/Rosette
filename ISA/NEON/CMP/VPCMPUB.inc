// CMP/VPCMPUB.inc
// ARM64/NEON translation mirror generated from ISA/x86/CMP/VPCMPUB.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VPCMPUB: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_integer_compare.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CMP/VPCMPUB.inc"
x86_handler = "x86_vpcmpub"
neon_lowering = "arm64_documented_contract_vpcmpub"
lowering_kind = "neon_mask_vector"

name = "VPCMPUB"
aliases = []
category = "simd_integer_compare"
feature = "AVX512BW"
element_type = "u8"
element_size = 8

encodings = [
  { opcode = "EVEX.128.66.0F3A.W0 3E /r ib", form = "VPCMPUB k1 {k2}, xmm2, xmm3/m128, imm8", op_en = "A", feature = "AVX512VL+AVX512BW", vector_length = 128, encoding = "evex", writes_mask = true, read_mask_dest = false, imm = 8 },
  { opcode = "EVEX.256.66.0F3A.W0 3E /r ib", form = "VPCMPUB k1 {k2}, ymm2, ymm3/m256, imm8", op_en = "A", feature = "AVX512VL+AVX512BW", vector_length = 256, encoding = "evex", writes_mask = true, read_mask_dest = false, imm = 8 },
  { opcode = "EVEX.512.66.0F3A.W0 3E /r ib", form = "VPCMPUB k1 {k2}, zmm2, zmm3/m512, imm8", op_en = "A", feature = "AVX512BW", vector_length = 512, encoding = "evex", writes_mask = true, read_mask_dest = false, imm = 8 }
]

operand_encoding = {
  A = ["ModRM:reg (w, opmask)", "EVEX.vvvv (r)", "ModRM:r/m (r)", "imm8 (r)"]
}

lanes = { xmm = 16, ymm = 32, zmm = 64 }
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
(KL, VL) = (16, 128), (32, 256), (64, 512);
for each active byte lane selected by k2 or no writemask:
    CMP = unsigned_compare(SRC1.u8[lane], SRC2.u8[lane], predicate);
    if CMP is true:
        DEST.bit[lane] = 1;
    else:
        DEST.bit[lane] = 0;
DEST[MAX_OPMASK_BITS-1:VL] = 0;
"""

handler = "x86_vpcmpub"
jit_lowering = "arm64_documented_contract_vpcmpub"
fallback = "zig_mask_loop_icmp_ub"

neon_register_model = """
x86 XMM/YMM/ZMM byte lanes are compared unsigned via ARM64 vector instructions; the result is packed into an opmask register.
"""

neon_flag_model = """
No x86 flags are modified; no MXCSR side-effects occur.
"""

neon_assembly = """
// VPCMPUB: unsigned byte comparison with predicate to opmask.
// ARM64: CMHI/CMHS/CMEQ for unsigned byte lanes.
// For predicate 0 (EQ): cmeq vT.16b, vN.16b, vM.16b
// For predicate 1 (LT): cmhi vT.16b, vM.16b, vN.16b (unsigned, swapped)
// For predicate 2 (LE): cmhs vT.16b, vM.16b, vN.16b (unsigned, swapped)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, writemask, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
