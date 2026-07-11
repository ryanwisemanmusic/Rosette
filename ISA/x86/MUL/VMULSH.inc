// VMULSH.inc

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VMULSH: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_float_scalar_mul.
"""

name = "VMULSH"
category = "simd_float_scalar_mul"
feature = "AVX512-FP16"
element_type = "f16"

encodings = [
  { opcode = "EVEX.LLIG.F3.MAP5.W0 59 /r", form = "VMULSH xmm1{k1}{z}, xmm2, xmm3/m16{er}", op_en = "A", feature = "AVX512-FP16" }
]

element_size = 16
lane_type = "scalar_half_precision_float"

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
    DEST.f16[0] = SRC1.f16[0] * SRC2.f16[0];
else if zero_masking:
    DEST.f16[0] = 0;
DEST[127:16] = SRC1[127:16];
DEST[MAXVL-1:128] = 0;
"""

handler = "x86_vmulsh"
jit_lowering = "arm64_neon_fmul_scalar"
fallback = "zig_lane_loop"
