// VMINPH.inc

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VMINPH: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_float_packed_min_h.
"""

name = "VMINPH"
category = "simd_float_packed_min_h"
feature = "AVX512-FP16"
element_type = "f16"

encodings = [
  { opcode = "EVEX.128.NP.MAP5.W0 5D /r", form = "VMINPH xmm1{k1}{z}, xmm2, xmm3/m128/m16bcst", op_en = "A", feature = "AVX512-FP16 AVX512VL" },
  { opcode = "EVEX.256.NP.MAP5.W0 5D /r", form = "VMINPH ymm1{k1}{z}, ymm2, ymm3/m256/m16bcst", op_en = "A", feature = "AVX512-FP16 AVX512VL" },
  { opcode = "EVEX.512.NP.MAP5.W0 5D /r", form = "VMINPH zmm1{k1}{z}, zmm2, zmm3/m512/m16bcst{sae}", op_en = "A", feature = "AVX512-FP16" }
]

element_size = 16
lane_type = "half_precision_float"

lanes = {
  xmm = 8,
  ymm = 16,
  zmm = 32
}

mxcsr_used = false

simd_fp_exceptions = [
  "invalid",
  "denormal"
]

flags_written = []

semantic_evex = """
for lane in VL/16:
    if writemask_enabled:
        DEST.f16[lane] = MIN(SRC1.f16[lane], SRC2.f16[lane]);
    else if zero_masking:
        DEST.f16[lane] = 0;
DEST[MAXVL-1:VL] = 0;
"""

handler = "x86_vminph"
jit_lowering = "arm64_neon_fmin_packed"
fallback = "zig_lane_loop"
