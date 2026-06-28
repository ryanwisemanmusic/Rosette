// RSQRTPS.inc

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
RSQRTPS: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_floating_point.
"""

name = "RSQRTPS"
category = "simd_floating_point"
feature = "SSE"
element_type = "f32"

encodings = [
  { opcode = "NP 0F 52 /r", form = "RSQRTPS xmm1, xmm2/m128", op_en = "A", feature = "SSE" },
  { opcode = "VEX.128.0F.WIG 52 /r", form = "VRSQRTPS xmm1, xmm2, xmm3/m128", op_en = "B", feature = "AVX" },
  { opcode = "VEX.256.0F.WIG 52 /r", form = "VRSQRTPS ymm1, ymm2, ymm3/m256", op_en = "B", feature = "AVX" }
]

element_size = 32
lane_type = "single_precision_float"

lanes = {
  xmm = 4,
  ymm = 8
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

semantic_legacy_128 = """
DEST.f32[0] = approx_reciprocal_sqrt(DEST.f32[0]);
DEST.f32[1] = approx_reciprocal_sqrt(DEST.f32[1]);
DEST.f32[2] = approx_reciprocal_sqrt(DEST.f32[2]);
DEST.f32[3] = approx_reciprocal_sqrt(DEST.f32[3]);
DEST[MAXVL-1:128] unchanged;
"""

semantic_vex_128 = """
DEST.f32[0] = approx_reciprocal_sqrt(SRC1.f32[0]);
DEST.f32[1] = approx_reciprocal_sqrt(SRC1.f32[1]);
DEST.f32[2] = approx_reciprocal_sqrt(SRC1.f32[2]);
DEST.f32[3] = approx_reciprocal_sqrt(SRC1.f32[3]);
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
DEST.f32[0] = approx_reciprocal_sqrt(SRC1.f32[0]);
DEST.f32[1] = approx_reciprocal_sqrt(SRC1.f32[1]);
DEST.f32[2] = approx_reciprocal_sqrt(SRC1.f32[2]);
DEST.f32[3] = approx_reciprocal_sqrt(SRC1.f32[3]);
DEST.f32[4] = approx_reciprocal_sqrt(SRC1.f32[4]);
DEST.f32[5] = approx_reciprocal_sqrt(SRC1.f32[5]);
DEST.f32[6] = approx_reciprocal_sqrt(SRC1.f32[6]);
DEST.f32[7] = approx_reciprocal_sqrt(SRC1.f32[7]);
DEST[MAXVL-1:256] = 0;
"""

handler = "x86_rsqrtps"
jit_lowering = "arm64_neon_frsqrte_ps"
fallback = "zig_lane_loop"
