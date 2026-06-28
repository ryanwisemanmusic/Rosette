// SQRTSS.inc

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
SQRTSS: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_floating_point.
"""

name = "SQRTSS"
category = "simd_floating_point"
feature = "SSE"
element_type = "f32"

encodings = [
  { opcode = "F3 0F 51 /r", form = "SQRTSS xmm1, xmm2/m32", op_en = "A", feature = "SSE" },
  { opcode = "VEX.LIG.F3.0F.WIG 51 /r", form = "VSQRTSS xmm1, xmm2, xmm3/m32", op_en = "B", feature = "AVX" },
  { opcode = "EVEX.LLIG.F3.0F.W0 51 /r", form = "VSQRTSS xmm1{k1}{z}, xmm2, xmm3/m32{er}", op_en = "C", feature = "AVX512F" }
]

element_size = 32
lane_type = "scalar_single_precision_float"

mxcsr_used = true

simd_fp_exceptions = [
  "overflow",
  "underflow",
  "invalid",
  "precision",
  "denormal"
]

flags_written = []

semantic_legacy_128 = """
DEST.f32[0] = sqrt(DEST.f32[0]);
DEST[MAXVL-1:32] unchanged;
"""

semantic_vex_128 = """
DEST.f32[0] = sqrt(SRC2.f32[0]);
DEST.f32[1] = SRC1.f32[1];
DEST.f32[2] = SRC1.f32[2];
DEST.f32[3] = SRC1.f32[3];
DEST[MAXVL-1:128] = 0;
"""

semantic_evex = """
if k1[0] or no writemask:
    DEST.f32[0] = sqrt(SRC2.f32[0]);
else if zero_masking:
    DEST.f32[0] = 0;
DEST.f32[1] = SRC1.f32[1];
DEST.f32[2] = SRC1.f32[2];
DEST.f32[3] = SRC1.f32[3];
DEST[MAXVL-1:128] = 0;
"""

handler = "x86_sqrtss"
jit_lowering = "arm64_scalar_fsqrt_s"
