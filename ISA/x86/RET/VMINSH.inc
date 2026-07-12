// VMINSH.inc

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VMINSH: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_float_scalar_min_h.
"""

name = "VMINSH"
category = "simd_float_scalar_min_h"
feature = "AVX512-FP16"
element_type = "f16"

encodings = [
  { opcode = "EVEX.LLIG.F3.MAP5.W0 5D /r", form = "VMINSH xmm1{k1}{z}, xmm2, xmm3/m16{er}", op_en = "A", feature = "AVX512-FP16" }
]

element_size = 16
lane_type = "half_precision_float"

lanes = {
  xmm = 8,
  ymm = 0,
  zmm = 0
}

mxcsr_used = false

simd_fp_exceptions = [
  "invalid",
  "denormal"
]

flags_written = []

semantic_evex = """
IF k1[0] or *no writemask*:
    DEST.f16[0] = MIN(SRC1.f16[0], SRC2.f16[0]);
ELSE IF *zero-masking*:
    DEST.f16[0] = 0;
ELSE:
    *merge-masking*: DEST.f16[0] unchanged;
DEST[MAXVL-1:16] = 0;
"""

handler = "x86_vminsh"
jit_lowering = "arm64_neon_fmin_scalar"
fallback = "zig_lane_loop"
