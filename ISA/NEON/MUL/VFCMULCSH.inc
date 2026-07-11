// MUL/VFCMULCSH.inc
// ARM64/NEON translation mirror generated from ISA/x86/MUL/VFCMULCSH.inc.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VFCMULCSH: preserve the operation and form-specific semantic blocks.
Category: simd_fp_complex_mul_scalar.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "MUL/VFCMULCSH.inc"
x86_handler = "x86_vfcmulcsh"
neon_lowering = "arm64_neon_fcmla_scalar"
lowering_kind = "neon_scalar"

name = "VFCMULCSH"
category = "simd_fp_complex_mul_scalar"
feature = "AVX512-FP16"
element_type = "f16"

encodings = [
  { opcode = "EVEX.LLIG.66.0F3A.W0 9F /r /ib", form = "VFCMULCSH xmm1 {k1}{z}, xmm2, xmm3/m16, imm8", op_en = "C", feature = "AVX512-FP16" },
]

element_size = 16
lane_type = "scalar_half_precision_float"

lanes = {
  xmm = 1,
  ymm = 1,
  zmm = 1
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
// No legacy SSE variant; AVX512-FP16 only.
"""

semantic_vex_128 = """
// No VEX variant; AVX512-FP16 only.
"""

semantic_vex_256 = """
// No VEX variant; AVX512-FP16 only.
"""

semantic_evex = """
if k1[0] or no writemask:
    a_re = SRC1.f16[0];
    a_im = SRC1.f16[1];
    b_re = SRC2.f16[0];
    b_im = SRC2.f16[1];
    DEST.f16[0] = a_re * b_re + a_im * b_im;
    DEST.f16[1] = a_re * b_im - a_im * b_re;
else if zero_masking:
    DEST.f16[0] = 0;
    DEST.f16[1] = 0;
DEST[MAXVL-1:128] unchanged for upper lanes;
"""

handler = "x86_vfcmulcsh"
jit_lowering = "arm64_neon_fcmla_scalar"
fallback = "zig_lane_loop"

neon_register_model = """
x86 scalar complex operand is placed in lanes 0-1 of an ARM64 v register; upper lanes preserve the first source.
"""

neon_flag_model = """
MXCSR exception/status behavior is preserved through Rosette SIMD floating-point side-effect handlers.
"""

neon_assembly = """
fcmla vD.4h, vN.4h, vM.4h, #0
bl rosette_merge_scalar_high_lanes
bl rosette_apply_mxcsr_float_exceptions
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
