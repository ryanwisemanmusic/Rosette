// BLEND/VPBLENDD.inc
// ARM64/NEON mirror generated from ISA/x86/BLEND/VPBLENDD.inc.
// This file preserves the x86 source contract and supplies the ARM64 lowering contract.

// Canonical table metadata for registry-wide .inc validation.
semantic = """
VPBLENDD: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_blend.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "BLEND/VPBLENDD.inc"
x86_handler = "x86_vpblendd"
neon_lowering = "arm64_neon_vpblendd"
lowering_kind = "arm64_documented_contract"

// BLEND/VPBLENDD.inc
// ARM64/NEON translation mirror generated from ISA/x86/BLEND/VPBLENDD.inc.
// Source contract: VPBLENDD — Blend Packed Dwords.

name = "VPBLENDD"
aliases = []
category = "simd_blend"
feature = "AVX2"
element_type = "i32"
element_size = 32

encodings = [
  { opcode = "VEX.128.66.0F3A.W0 02 /r ib", form = "VPBLENDD xmm1, xmm2, xmm3/m128, imm8", op_en = "RVMI", feature = "AVX2", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F3A.W0 02 /r ib", form = "VPBLENDD ymm1, ymm2, ymm3/m256, imm8", op_en = "RVMI", feature = "AVX2", vector_length = 256, encoding = "vex" }
]

operand_encoding = {
  RVMI = ["ModRM:reg (w)", "VEX.vvvv (r)", "ModRM:r/m (r)", "imm8"]
}

lanes = { xmm = 4, ymm = 8 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "See Table 2-21, \"Type 4 Class Exception Conditions.\"",
  "#UD If VEX.W = 1."
]

semantic_vex_128 = """
IF (imm8[0] == 1) THEN DEST[31:0] := SRC2[31:0]
    ELSE DEST[31:0] := SRC1[31:0] FI
IF (imm8[1] == 1) THEN DEST[63:32] := SRC2[63:32]
    ELSE DEST[63:32] := SRC1[63:32] FI
IF (imm8[2] == 1) THEN DEST[95:64] := SRC2[95:64]
    ELSE DEST[95:64] := SRC1[95:64] FI
IF (imm8[3] == 1) THEN DEST[127:96] := SRC2[127:96]
    ELSE DEST[127:96] := SRC1[127:96] FI
DEST[MAXVL-1:128] := 0
"""

semantic_vex_256 = """
IF (imm8[0] == 1) THEN DEST[31:0] := SRC2[31:0]
    ELSE DEST[31:0] := SRC1[31:0] FI
IF (imm8[1] == 1) THEN DEST[63:32] := SRC2[63:32]
    ELSE DEST[63:32] := SRC1[63:32] FI
IF (imm8[2] == 1) THEN DEST[95:64] := SRC2[95:64]
    ELSE DEST[95:64] := SRC1[95:64] FI
IF (imm8[3] == 1) THEN DEST[127:96] := SRC2[127:96]
    ELSE DEST[127:96] := SRC1[127:96] FI
IF (imm8[4] == 1) THEN DEST[159:128] := SRC2[159:128]
    ELSE DEST[159:128] := SRC1[159:128] FI
IF (imm8[5] == 1) THEN DEST[191:160] := SRC2[191:160]
    ELSE DEST[191:160] := SRC1[191:160] FI
IF (imm8[6] == 1) THEN DEST[223:192] := SRC2[223:192]
    ELSE DEST[223:192] := SRC1[223:192] FI
IF (imm8[7] == 1) THEN DEST[255:224] := SRC2[255:224]
    ELSE DEST[255:224] := SRC1[255:224] FI
DEST[MAXVL-1:256] := 0
"""

handler = "x86_vpblendd"
jit_lowering = "arm64_neon_vpblendd"
fallback = "zig_lane_loop_blend_32"

neon_register_model = """
x86 xmm/ymm bit lanes are mapped into ARM64 vector temporaries. VPBLENDD is a per-dword select using immediate mask bits. No MXCSR floating-point exception state is generated.
"""

neon_flag_model = """
No x86 flags are modified by VPBLENDD.
"""

neon_assembly = """
// NEON lowering: bsl with mask generated from imm8
// For 128-bit: generate 32-bit lane mask from imm8[3:0], apply bsl vD.16b, vN.16b, vM.16b
// For 256-bit: generate 32-bit lane mask from imm8[7:0], apply bsl across both 128-bit halves
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, writemask, broadcast, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
