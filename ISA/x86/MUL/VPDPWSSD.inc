// VPDPWSSD.inc

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VPDPWSSD: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_int_dot_product.
"""

name = "VPDPWSSD"
category = "simd_int_dot_product"
feature = "AVX-VNNI"
element_type = "i16"

encodings = [
  { opcode = "VEX.128.66.0F38.W0 52 /r", form = "VPDPWSSD xmm1, xmm2, xmm3/m128", op_en = "A", feature = "AVX-VNNI" },
  { opcode = "VEX.256.66.0F38.W0 52 /r", form = "VPDPWSSD ymm1, ymm2, ymm3/m256", op_en = "A", feature = "AVX-VNNI" },
  { opcode = "EVEX.128.66.0F38.W0 52 /r", form = "VPDPWSSD xmm1{k1}{z}, xmm2, xmm3/m128/m32bcst", op_en = "B", feature = "AVX512_VNNI" },
  { opcode = "EVEX.256.66.0F38.W0 52 /r", form = "VPDPWSSD ymm1{k1}{z}, ymm2, ymm3/m256/m32bcst", op_en = "B", feature = "AVX512_VNNI" },
  { opcode = "EVEX.512.66.0F38.W0 52 /r", form = "VPDPWSSD zmm1{k1}{z}, ymm2, zmm3/m512/m32bcst", op_en = "B", feature = "AVX512_VNNI" }
]

element_size = 32
lane_type = "signed_dword"

lanes = {
  xmm = 4,
  ymm = 8,
  zmm = 16
}

mxcsr_used = false

simd_fp_exceptions = []

flags_written = []

semantic_vex_128 = """
ORIGDEST = DEST;
for i in 0..3:
    p1 = SIGN_EXTEND(SRC1.s16[2*i+0]) * SIGN_EXTEND(SRC2.s16[2*i+0]);
    p2 = SIGN_EXTEND(SRC1.s16[2*i+1]) * SIGN_EXTEND(SRC2.s16[2*i+1]);
    DEST.s32[i] = ORIGDEST.s32[i] + p1 + p2;
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
ORIGDEST = DEST;
for i in 0..7:
    p1 = SIGN_EXTEND(SRC1.s16[2*i+0]) * SIGN_EXTEND(SRC2.s16[2*i+0]);
    p2 = SIGN_EXTEND(SRC1.s16[2*i+1]) * SIGN_EXTEND(SRC2.s16[2*i+1]);
    DEST.s32[i] = ORIGDEST.s32[i] + p1 + p2;
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
ORIGDEST = DEST;
for i in VL/32:
    if writemask_enabled:
        if broadcasting:
            t = SRC2.dword[0];
        else:
            t = SRC2.dword[i];
        p1 = SIGN_EXTEND(SRC1.s16[2*i+0]) * SIGN_EXTEND(t.s16[0]);
        p2 = SIGN_EXTEND(SRC1.s16[2*i+1]) * SIGN_EXTEND(t.s16[1]);
        DEST.s32[i] = ORIGDEST.s32[i] + p1 + p2;
    else if zero_masking:
        DEST.s32[i] = 0;
DEST[MAXVL-1:VL] = 0;
"""

handler = "x86_vpdpwssd"
jit_lowering = "arm64_neon_sdot_v8i16"
fallback = "zig_lane_loop"
