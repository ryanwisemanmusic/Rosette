// VMAXSH.inc

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VMAXSH: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_float_scalar_max_h.
"""

name = "VMAXSH"
category = "simd_float_scalar_max_h"
feature = "AVX512-FP16"
element_type = "f16"

encodings = [
  { opcode = "EVEX.LLIG.F3.MAP5.W0 5F /r", form = "VMAXSH xmm1{k1}{z}, xmm2, xmm3/m16{er}", op_en = "A", feature = "AVX512-FP16" }
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
    DEST.f16[0] = MAX(SRC1.f16[0], SRC2.f16[0]);
ELSE IF *zero-masking*:
    DEST.f16[0] = 0;
ELSE:
    *merge-masking*: DEST.f16[0] unchanged;
DEST[MAXVL-1:16] = 0;
"""

handler = "x86_vmaxsh"
jit_lowering = "arm64_neon_fmax_scalar"
fallback = "zig_lane_loop"
