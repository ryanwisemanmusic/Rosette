// VFMULCSH.inc

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VFMULCSH: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_float_scalar_complex_mul.
"""

name = "VFMULCSH"
category = "simd_float_scalar_complex_mul"
feature = "AVX512-FP16"
element_type = "f16"

encodings = [
  { opcode = "EVEX.LLIG.F3.MAP6.W0 D7 /r", form = "VFMULCSH xmm1{k1}{z}, xmm2, xmm3/m32{er}", op_en = "A", feature = "AVX512-FP16" }
]

element_size = 16
lane_type = "scalar_complex_half_precision_float"

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
if k1[0] or no writemask:
    a = SRC1.f16[0];
    b = SRC1.f16[1];
    c = SRC2.f16[0];
    d = SRC2.f16[1];
    DEST.f16[0] = a*c - b*d;
    DEST.f16[1] = b*c + a*d;
else if zero_masking:
    DEST.f32[0] = 0;
DEST[127:32] = SRC1[127:32];
DEST[MAXVL-1:128] = 0;
"""

handler = "x86_vfmulcsh"
jit_lowering = "arm64_neon_fcmla_scalar"
fallback = "zig_lane_loop"
