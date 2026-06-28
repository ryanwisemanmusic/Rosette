// COMPUTE/RSQRTPS.inc
// ARM64/NEON translation mirror generated from ISA/x86/COMPUTE/RSQRTPS.inc.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
RSQRTPS: preserve the operation and form-specific semantic blocks.
Category: simd_floating_point.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "COMPUTE/RSQRTPS.inc"
x86_handler = "x86_rsqrtps"
neon_lowering = "arm64_neon_frsqrte_ps"
lowering_kind = "neon_vector"

name = "RSQRTPS"
category = "simd_floating_point"
feature = "SSE_AVX"
element_type = "f32"

encodings = [
  { opcode = "NP 0F 52 /r", form = "RSQRTPS xmm1, xmm2/m128", op_en = "A", feature = "SSE", vector_length = 128, encoding = "legacy_sse" },
  { opcode = "VEX.128.0F.WIG 52 /r", form = "VRSQRTPS xmm1, xmm2, xmm3/m128", op_en = "B", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.0F.WIG 52 /r", form = "VRSQRTPS ymm1, ymm2, ymm3/m256", op_en = "B", feature = "AVX", vector_length = 256, encoding = "vex" }
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

neon_register_model = """
x86 xmm/ymm lanes are mapped onto ARM64 v registers; each f32 lane receives the reciprocal sqrt estimate.
"""

neon_flag_model = """
No x86 flags are modified; MXCSR exception/status behavior is preserved through Rosette SIMD floating-point side-effect handlers.
"""

neon_assembly = """
frsqrte vD.4s, vN.4s
// For 256-bit: frsqrte vD.4s, vN_low.4s; frsqrte vD_high.4s, vN_high.4s
bl rosette_apply_mxcsr_float_exceptions
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
