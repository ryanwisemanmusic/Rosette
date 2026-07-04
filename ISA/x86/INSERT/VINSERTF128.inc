// INSERT/VINSERTF128.inc
// ARM64/NEON translation mirror generated from ISA/x86/INSERT/VINSERTF128.inc.
// Source contract: VINSERTF128 — Insert Packed Single Precision Floating-Point Values.

// Canonical table metadata for registry-wide .inc validation.
semantic = """
VINSERTF128: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_insert.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INSERT/VINSERTF128.inc"
x86_handler = "x86_vinsertf128"
neon_lowering = "arm64_insert_f32x4_subvector"
lowering_kind = "arm64_documented_contract"

name = "VINSERTF128"
aliases = []
category = "simd_insert"
feature = "AVX"
element_type = "f32x4_insert"
element_size = 128

encodings = [
  { opcode = "VEX.256.66.0F3A.W0 18 /r ib", form = "VINSERTF128 ymm1, ymm2, xmm3/m128, imm8", op_en = "RVMI", feature = "AVX", vector_length = 256, encoding = "vex" }
]

operand_encoding = {
  RVMI = ["ModRM:reg (w)", "VEX.vvvv (r)", "ModRM:r/m (r)", "imm8"]
}

lanes = { ymm = 8 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "See Table 2-21, \"Type 4 Class Exception Conditions,\" additionally:",
  "#UD If VEX.L != 1 (only 256-bit encoding valid)."
]

semantic_vex_256 = """
CASE imm8[0] OF:
    0: DEST[127:0]   := SRC2[127:0];
       DEST[255:128] := SRC1[255:128];
    1: DEST[127:0]   := SRC1[127:0];
       DEST[255:128] := SRC2[127:0];
DEST[MAXVL-1:256] := 0;
"""

handler = "x86_vinsertf128"
jit_lowering = "arm64_insert_subvector"
fallback = "zig_insert_lane"

neon_register_model = """
x86 ymm is represented as two ARM64 128-bit vectors. VINSERTF128 inserts a 128-bit sub-vector from SRC2 into the low or high half of the destination YMM register, selected by imm8[0].
"""

neon_flag_model = """
No x86 flags are modified by VINSERTF128.
"""

neon_assembly = """
// NEON lowering: for imm8[0]=0, mov vD.16b, vSRC2.16b; mov vD2.16b, vSRC1_hi.16b
// For imm8[0]=1, mov vD.16b, vSRC1_lo.16b; mov vD2.16b, vSRC2.16b
// where vD/vD2 represent the low/high 128-bit halves of ymm
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, writemask, broadcast, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape.",
  "256-bit YMM is lowered as two 128-bit NEON registers (vD.lo, vD.hi)."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
