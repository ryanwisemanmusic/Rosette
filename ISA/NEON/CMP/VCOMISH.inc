// CMP/VCOMISH.inc
// ARM64/NEON translation mirror generated from ISA/x86/CMP/VCOMISH.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VCOMISH: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_scalar_float_compare.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CMP/VCOMISH.inc"
x86_handler = "x86_vcomish"
neon_lowering = "arm64_documented_contract_vcomish"
lowering_kind = "neon_scalar_flags"

name = "VCOMISH"
aliases = []
category = "simd_scalar_float_compare"
feature = "AVX512-FP16"
element_type = "f16"
element_size = 16

encodings = [
  { opcode = "EVEX.LLIG.66.0F3A.W0 2F /r", form = "VCOMISH xmm1, xmm2/m16", op_en = "A", feature = "AVX512-FP16", vector_length = 0, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (r, w)", "ModRM:r/m (r)"]
}

active_lane = 0
lane_type = "scalar_half_precision"

lanes = { xmm = 8, ymm = 16, zmm = 32 }
flags_written = ["ZF", "PF", "CF"]
mxcsr_used = true

simd_fp_exceptions = ["Invalid", "Denormal"]

semantic_evex_scalar = """
CMP = compare_ordered(SRC1.f16[0], SRC2.f16[0]);
ZF = 1 if SRC1 == SRC2 else 0;
PF = 1 if either operand is NaN (unordered) else 0;
CF = 1 if SRC1 < SRC2 else 0;
OF = 0;
AF = 0;
SF = 0;
DEST.f16[0] = SRC1.f16[0];
DEST[127:16] = SRC1[127:16];
DEST[MAXVL-1:128] = 0;
"""

handler = "x86_vcomish"
jit_lowering = "arm64_documented_contract_vcomish"
fallback = "zig_scalar_fcmp_h_flags"

neon_register_model = """
x86 scalar FP16 lane (xmm[15:0]) is mapped onto an ARM64 h-register; the comparison sets x86 EFLAGS via ARM64 NZCV mapping.
"""

neon_flag_model = """
ARM64 FCMP provides NZCV for unordered/equal/less-than/greater-than results, which must be mapped to x86 ZF/PF/CF.
When either operand is NaN: ARM64 sets NV (V=1, C=1), which maps to x86 PF=1, ZF=0, CF=0.
When both operands are equal: ARM64 sets Z=1, maps to x86 ZF=1, PF=0, CF=0.
When SRC1 < SRC2: ARM64 sets N=1, C=0, maps to x86 CF=1, ZF=0, PF=0.
When SRC1 > SRC2: ARM64 sets N=0, C=1, Z=0, maps to x86 CF=0, ZF=0, PF=0.
"""

neon_assembly = """
// ARM64 FP compare for half precision.
//     fcmp hN, hM
//     mrs  xNZCV, nzcv
//     bl   rosette_pack_x86_comi_flags  // maps NZCV to ZF/PF/CF
// DEST register retains SRC1 value.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "VCOMISH performs an ordered comparison and sets ZF/PF/CF exactly as COMISS/COMISD do for other float types.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
