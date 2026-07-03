// BLEND/PBLENDVB.inc
// ARM64/NEON mirror generated from ISA/x86/BLEND/PBLENDVB.inc.
// This file preserves the x86 source contract and supplies the ARM64 lowering contract.

// Canonical table metadata for registry-wide .inc validation.
semantic = """
PBLENDVB: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_variable_blend.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "BLEND/PBLENDVB.inc"
x86_handler = "x86_pblendvb"
neon_lowering = "arm64_neon_pblendvb"
lowering_kind = "arm64_documented_contract"

// BLEND/PBLENDVB.inc
// ARM64/NEON translation mirror generated from ISA/x86/BLEND/PBLENDVB.inc.
// Source contract: PBLENDVB/VPBLENDVB — Variable Blend Packed Bytes.

name = "PBLENDVB"
aliases = ["VPBLENDVB"]
category = "simd_variable_blend"
feature = "SSE4_1_AVX_AVX2"
element_type = "i8"
element_size = 8

encodings = [
  { opcode = "66 0F 38 10 /r", form = "PBLENDVB xmm1, xmm2/m128, <XMM0>", op_en = "RM", feature = "SSE4_1", vector_length = 128, encoding = "legacy_sse" },
  { opcode = "VEX.128.66.0F3A.W0 4C /r /is4", form = "VPBLENDVB xmm1, xmm2, xmm3/m128, xmm4", op_en = "RVMR", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F3A.W0 4C /r /is4", form = "VPBLENDVB ymm1, ymm2, ymm3/m256, ymm4", op_en = "RVMR", feature = "AVX2", vector_length = 256, encoding = "vex" }
]

operand_encoding = {
  RM = ["ModRM:reg (r,w)", "ModRM:r/m (r)", "<XMM0>"],
  RVMR = ["ModRM:reg (w)", "VEX.vvvv (r)", "ModRM:r/m (r)", "imm8[7:4]"]
}

lanes = { xmm = 16, ymm = 32 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "See Table 2-21, \"Type 4 Class Exception Conditions,\" additionally:",
  "#UD If VEX.W = 1.",
  "#UD If VEX.L = 1 and AVX2 = 0."
]

semantic_legacy_128 = """
MASK := XMM0
IF (MASK[7] = 1) THEN DEST[7:0] := SRC[7:0]
    ELSE DEST[7:0] := DEST[7:0] FI
IF (MASK[15] = 1) THEN DEST[15:8] := SRC[15:8]
    ELSE DEST[15:8] := DEST[15:8] FI
IF (MASK[23] = 1) THEN DEST[23:16] := SRC[23:16]
    ELSE DEST[23:16] := DEST[23:16] FI
IF (MASK[31] = 1) THEN DEST[31:24] := SRC[31:24]
    ELSE DEST[31:24] := DEST[31:24] FI
IF (MASK[39] = 1) THEN DEST[39:32] := SRC[39:32]
    ELSE DEST[39:32] := DEST[39:32] FI
IF (MASK[47] = 1) THEN DEST[47:40] := SRC[47:40]
    ELSE DEST[47:40] := DEST[47:40] FI
IF (MASK[55] = 1) THEN DEST[55:48] := SRC[55:48]
    ELSE DEST[55:48] := DEST[55:48] FI
IF (MASK[63] = 1) THEN DEST[63:56] := SRC[63:56]
    ELSE DEST[63:56] := DEST[63:56] FI
IF (MASK[71] = 1) THEN DEST[71:64] := SRC[71:64]
    ELSE DEST[71:64] := DEST[71:64] FI
IF (MASK[79] = 1) THEN DEST[79:72] := SRC[79:72]
    ELSE DEST[79:72] := DEST[79:72] FI
IF (MASK[87] = 1) THEN DEST[87:80] := SRC[87:80]
    ELSE DEST[87:80] := DEST[87:80] FI
IF (MASK[95] = 1) THEN DEST[95:88] := SRC[95:88]
    ELSE DEST[95:88] := DEST[95:88] FI
IF (MASK[103] = 1) THEN DEST[103:96] := SRC[103:96]
    ELSE DEST[103:96] := DEST[103:96] FI
IF (MASK[111] = 1) THEN DEST[111:104] := SRC[111:104]
    ELSE DEST[111:104] := DEST[111:104] FI
IF (MASK[119] = 1) THEN DEST[119:112] := SRC[119:112]
    ELSE DEST[119:112] := DEST[119:112] FI
IF (MASK[127] = 1) THEN DEST[127:120] := SRC[127:120]
    ELSE DEST[127:120] := DEST[127:120] FI
DEST[MAXVL-1:128] (Unmodified)
"""

semantic_vex_128 = """
MASK := SRC3
IF (MASK[7] = 1) THEN DEST[7:0] := SRC2[7:0]
    ELSE DEST[7:0] := SRC1[7:0] FI
IF (MASK[15] = 1) THEN DEST[15:8] := SRC2[15:8]
    ELSE DEST[15:8] := SRC1[15:8] FI
IF (MASK[23] = 1) THEN DEST[23:16] := SRC2[23:16]
    ELSE DEST[23:16] := SRC1[23:16] FI
IF (MASK[31] = 1) THEN DEST[31:24] := SRC2[31:24]
    ELSE DEST[31:24] := SRC1[31:24] FI
IF (MASK[39] = 1) THEN DEST[39:32] := SRC2[39:32]
    ELSE DEST[39:32] := SRC1[39:32] FI
IF (MASK[47] = 1) THEN DEST[47:40] := SRC2[47:40]
    ELSE DEST[47:40] := SRC1[47:40] FI
IF (MASK[55] = 1) THEN DEST[55:48] := SRC2[55:48]
    ELSE DEST[55:48] := SRC1[55:48] FI
IF (MASK[63] = 1) THEN DEST[63:56] := SRC2[63:56]
    ELSE DEST[63:56] := SRC1[63:56] FI
IF (MASK[71] = 1) THEN DEST[71:64] := SRC2[71:64]
    ELSE DEST[71:64] := SRC1[71:64] FI
IF (MASK[79] = 1) THEN DEST[79:72] := SRC2[79:72]
    ELSE DEST[79:72] := SRC1[79:72] FI
IF (MASK[87] = 1) THEN DEST[87:80] := SRC2[87:80]
    ELSE DEST[87:80] := SRC1[87:80] FI
IF (MASK[95] = 1) THEN DEST[95:88] := SRC2[95:88]
    ELSE DEST[95:88] := SRC1[95:88] FI
IF (MASK[103] = 1) THEN DEST[103:96] := SRC2[103:96]
    ELSE DEST[103:96] := SRC1[103:96] FI
IF (MASK[111] = 1) THEN DEST[111:104] := SRC2[111:104]
    ELSE DEST[111:104] := SRC1[111:104] FI
IF (MASK[119] = 1) THEN DEST[119:112] := SRC2[119:112]
    ELSE DEST[119:112] := SRC1[119:112] FI
IF (MASK[127] = 1) THEN DEST[127:120] := SRC2[127:120]
    ELSE DEST[127:120] := SRC1[127:120] FI
DEST[MAXVL-1:128] := 0
"""

semantic_vex_256 = """
MASK := SRC3
IF (MASK[7] == 1) THEN DEST[7:0] := SRC2[7:0]
    ELSE DEST[7:0] := SRC1[7:0] FI
IF (MASK[15] == 1) THEN DEST[15:8] := SRC2[15:8]
    ELSE DEST[15:8] := SRC1[15:8] FI
IF (MASK[23] == 1) THEN DEST[23:16] := SRC2[23:16]
    ELSE DEST[23:16] := SRC1[23:16] FI
IF (MASK[31] == 1) THEN DEST[31:24] := SRC2[31:24]
    ELSE DEST[31:24] := SRC1[31:24] FI
IF (MASK[39] == 1) THEN DEST[39:32] := SRC2[39:32]
    ELSE DEST[39:32] := SRC1[39:32] FI
IF (MASK[47] == 1) THEN DEST[47:40] := SRC2[47:40]
    ELSE DEST[47:40] := SRC1[47:40] FI
IF (MASK[55] == 1) THEN DEST[55:48] := SRC2[55:48]
    ELSE DEST[55:48] := SRC1[55:48] FI
IF (MASK[63] == 1) THEN DEST[63:56] := SRC2[63:56]
    ELSE DEST[63:56] := SRC1[63:56] FI
IF (MASK[71] == 1) THEN DEST[71:64] := SRC2[71:64]
    ELSE DEST[71:64] := SRC1[71:64] FI
IF (MASK[79] == 1) THEN DEST[79:72] := SRC2[79:72]
    ELSE DEST[79:72] := SRC1[79:72] FI
IF (MASK[87] == 1) THEN DEST[87:80] := SRC2[87:80]
    ELSE DEST[87:80] := SRC1[87:80] FI
IF (MASK[95] == 1) THEN DEST[95:88] := SRC2[95:88]
    ELSE DEST[95:88] := SRC1[95:88] FI
IF (MASK[103] == 1) THEN DEST[103:96] := SRC2[103:96]
    ELSE DEST[103:96] := SRC1[103:96] FI
IF (MASK[111] == 1) THEN DEST[111:104] := SRC2[111:104]
    ELSE DEST[111:104] := SRC1[111:104] FI
IF (MASK[119] == 1) THEN DEST[119:112] := SRC2[119:112]
    ELSE DEST[119:112] := SRC1[119:112] FI
IF (MASK[127] == 1) THEN DEST[127:120] := SRC2[127:120]
    ELSE DEST[127:120] := SRC1[127:120] FI
IF (MASK[135] == 1) THEN DEST[135:128] := SRC2[135:128]
    ELSE DEST[135:128] := SRC1[135:128] FI
IF (MASK[143] == 1) THEN DEST[143:136] := SRC2[143:136]
    ELSE DEST[143:136] := SRC1[143:136] FI
IF (MASK[151] == 1) THEN DEST[151:144] := SRC2[151:144]
    ELSE DEST[151:144] := SRC1[151:144] FI
IF (MASK[159] == 1) THEN DEST[159:152] := SRC2[159:152]
    ELSE DEST[159:152] := SRC1[159:152] FI
IF (MASK[167] == 1) THEN DEST[167:160] := SRC2[167:160]
    ELSE DEST[167:160] := SRC1[167:160] FI
IF (MASK[175] == 1) THEN DEST[175:168] := SRC2[175:168]
    ELSE DEST[175:168] := SRC1[175:168] FI
IF (MASK[183] == 1) THEN DEST[183:176] := SRC2[183:176]
    ELSE DEST[183:176] := SRC1[183:176] FI
IF (MASK[191] == 1) THEN DEST[191:184] := SRC2[191:184]
    ELSE DEST[191:184] := SRC1[191:184] FI
IF (MASK[199] == 1) THEN DEST[199:192] := SRC2[199:192]
    ELSE DEST[199:192] := SRC1[199:192] FI
IF (MASK[207] == 1) THEN DEST[207:200] := SRC2[207:200]
    ELSE DEST[207:200] := SRC1[207:200] FI
IF (MASK[215] == 1) THEN DEST[215:208] := SRC2[215:208]
    ELSE DEST[215:208] := SRC1[215:208] FI
IF (MASK[223] == 1) THEN DEST[223:216] := SRC2[223:216]
    ELSE DEST[223:216] := SRC1[223:216] FI
IF (MASK[231] == 1) THEN DEST[231:224] := SRC2[231:224]
    ELSE DEST[231:224] := SRC1[231:224] FI
IF (MASK[239] == 1) THEN DEST[239:232] := SRC2[239:232]
    ELSE DEST[239:232] := SRC1[239:232] FI
IF (MASK[247] == 1) THEN DEST[247:240] := SRC2[247:240]
    ELSE DEST[247:240] := SRC1[247:240] FI
IF (MASK[255] == 1) THEN DEST[255:248] := SRC2[255:248]
    ELSE DEST[255:248] := SRC1[255:248] FI
DEST[MAXVL-1:256] := 0
"""

handler = "x86_pblendvb"
jit_lowering = "arm64_neon_pblendvb"
fallback = "zig_lane_loop_blendv_8"

neon_register_model = """
x86 xmm/ymm bit lanes are mapped into ARM64 vector temporaries. PBLENDVB is a per-byte select using sign bits from the mask register. The mask is applied via bsl. No MXCSR floating-point exception state is generated.
"""

neon_flag_model = """
No x86 flags are modified by PBLENDVB/VPBLENDVB.
"""

neon_assembly = """
// NEON lowering: bsl vD.16b, vMASK.16b, vN.16b, vM.16b
// The mask register sign bits select between first and second source operands.
// For legacy: XMM0 provides mask bits; for VEX: imm8[7:4] encodes mask register.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, writemask, broadcast, or implicit-operand behavior.",
  "PBLENDVB uses implicit XMM0 in legacy SSE form; VPBLENDVB encodes mask in imm8[7:4].",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
