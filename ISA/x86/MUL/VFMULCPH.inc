// VFMULCPH.inc

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VFMULCPH: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_float_complex_mul.
"""

name = "VFMULCPH"
category = "simd_float_complex_mul"
feature = "AVX512-FP16"
element_type = "f16"

encodings = [
  { opcode = "EVEX.128.F3.MAP6.W0 D6 /r", form = "VFMULCPH xmm1{k1}{z}, xmm2, xmm3/m128/m32bcst", op_en = "A", feature = "AVX512-FP16" },
  { opcode = "EVEX.256.F3.MAP6.W0 D6 /r", form = "VFMULCPH ymm1{k1}{z}, ymm2, ymm3/m256/m32bcst", op_en = "A", feature = "AVX512-FP16" },
  { opcode = "EVEX.512.F3.MAP6.W0 D6 /r", form = "VFMULCPH zmm1{k1}{z}, zmm2, zmm3/m512/m32bcst{er}", op_en = "A", feature = "AVX512-FP16" }
]

element_size = 16
lane_type = "complex_half_precision_float"

lanes = {
  xmm = 4,
  ymm = 8,
  zmm = 16
}

mxcsr_used = true

simd_fp_exceptions = [
  "overflow",
  "underflow",
  "invalid",
  "precision",
  "denormal"
]

flags_written = []

semantic_evex = """
for complex_pair in VL/32:
    if writemask_enabled:
        if broadcasting:
            t = SRC2.f32[0];
        else:
            t = SRC2.f32[complex_pair];
        a = SRC1.f16[2*complex_pair];
        b = SRC1.f16[2*complex_pair+1];
        c = t.f16[0];
        d = t.f16[1];
        DEST.f16[2*complex_pair] = a*c - b*d;
        DEST.f16[2*complex_pair+1] = b*c + a*d;
    else if zero_masking:
        DEST.f32[complex_pair] = 0;
DEST[MAXVL-1:VL] = 0;
"""

handler = "x86_vfmulcph"
jit_lowering = "arm64_neon_fcmla"
fallback = "zig_lane_loop"
