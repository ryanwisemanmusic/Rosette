// MAXSS.inc

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
MAXSS: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_float_scalar_max.
"""

name = "MAXSS"
category = "simd_float_scalar_max"
feature = "SSE"
element_type = "f32"

encodings = [
  { opcode = "F3 0F 5F /r", form = "MAXSS xmm1, xmm2/m32", op_en = "A", feature = "SSE" },
  { opcode = "VEX.LIG.F3.0F.WIG 5F /r", form = "VMAXSS xmm1, xmm2, xmm3/m32", op_en = "B", feature = "AVX" },
  { opcode = "EVEX.LLIG.F3.0F.W0 5F /r", form = "VMAXSS xmm1{k1}{z}, xmm2, xmm3/m32{er}", op_en = "C", feature = "AVX512F" }
]

element_size = 32
lane_type = "single_precision_float"

lanes = {
  xmm = 4,
  ymm = 0,
  zmm = 0
}

mxcsr_used = true

simd_fp_exceptions = [
  "invalid",
  "denormal"
]

flags_written = []

semantic_legacy_128 = """
DEST.f32[0] = MAX(DEST.f32[0], SRC.f32[0]);
DEST[MAXVL-1:32] unchanged;
"""

semantic_vex_128 = """
DEST.f32[0] = MAX(SRC1.f32[0], SRC2.f32[0]);
DEST[MAXVL-1:32] = 0;
"""

semantic_evex = """
IF k1[0] or *no writemask*:
    DEST.f32[0] = MAX(SRC1.f32[0], SRC2.f32[0]);
ELSE IF *zero-masking*:
    DEST.f32[0] = 0;
ELSE:
    *merge-masking*: DEST.f32[0] unchanged;
DEST[MAXVL-1:32] = 0;
"""

handler = "x86_maxss"
jit_lowering = "arm64_neon_fmax_scalar"
fallback = "zig_lane_loop"
