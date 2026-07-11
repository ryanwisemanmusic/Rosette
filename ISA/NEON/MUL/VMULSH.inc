// MUL/VMULSH.inc
// ARM64/NEON translation mirror generated from ISA/x86/MUL/VMULSH.inc.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VMULSH: preserve the operation and form-specific semantic blocks.
Category: simd_fp_mul_scalar.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "MUL/VMULSH.inc"
x86_handler = "x86_vmulsh"
neon_lowering = "arm64_neon_fmul_scalar_f16"
lowering_kind = "neon_scalar"

name = "VMULSH"
category = "simd_fp_mul_scalar"
feature = "AVX512-FP16"
element_type = "f16"

encodings = [
  { opcode = "EVEX.LLIG.66.0F.W0 59 /r", form = "VMULSH xmm1 {k1}{z}, xmm2, xmm3/m16{er}", op_en = "C", feature = "AVX512-FP16" },
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
    DEST.f16[0] = SRC1.f16[0] * SRC2.f16[0];
else if zero_masking:
    DEST.f16[0] = 0;
DEST.f16[1] = SRC1.f16[1];
DEST[MAXVL-1:128] unchanged for upper lanes;
"""

handler = "x86_vmulsh"
jit_lowering = "arm64_neon_fmul_scalar_f16"
fallback = "zig_lane_loop"

neon_register_model = """
x86 scalar FP16 operand is placed in lane 0 of an ARM64 v register; upper lanes preserve the first source.
"""

neon_flag_model = """
MXCSR exception/status behavior is preserved through Rosette SIMD floating-point side-effect handlers.
"""

neon_assembly = """
fj mul sD, sN, sM
bl rosette_merge_scalar_high_lanes
bl rosette_apply_mxcsr_float_exceptions
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
