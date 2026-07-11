// MUL/VFCMULCPH.inc
// ARM64/NEON translation mirror generated from ISA/x86/MUL/VFCMULCPH.inc.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VFCMULCPH: preserve the operation and form-specific semantic blocks.
Category: simd_fp_complex_mul.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "MUL/VFCMULCPH.inc"
x86_handler = "x86_vfcmulcph"
neon_lowering = "arm64_neon_fcmla"
lowering_kind = "neon_vector"

name = "VFCMULCPH"
category = "simd_fp_complex_mul"
feature = "AVX512-FP16"
element_type = "f16"

encodings = [
  { opcode = "EVEX.128.66.0F3A.W0 9D /r /ib", form = "VFCMULCPH xmm1 {k1}{z}, xmm2, xmm3/m128, imm8", op_en = "C", feature = "AVX512-FP16" },
  { opcode = "EVEX.256.66.0F3A.W0 9D /r /ib", form = "VFCMULCPH ymm1 {k1}{z}, ymm2, ymm3/m256, imm8", op_en = "C", feature = "AVX512-FP16 AVX512VL" },
  { opcode = "EVEX.512.66.0F3A.W0 9D /r /ib", form = "VFCMULCPH zmm1 {k1}{z}, zmm2, zmm3/m512, imm8", op_en = "C", feature = "AVX512-FP16" },
]

element_size = 16
lane_type = "half_precision_float"

lanes = {
  xmm = 8,
  ymm = 16,
  zmm = 32
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
for lane in VL in pairs (complex):
    if writemask_enabled:
        a_re = SRC1.f16[lane];
        a_im = SRC1.f16[lane+1];
        b_re = SRC2.f16[lane];
        b_im = SRC2.f16[lane+1];
        DEST.f16[lane]   = a_re * b_re + a_im * b_im;
        DEST.f16[lane+1] = a_re * b_im - a_im * b_re;
    else if zero_masking:
        DEST.f16[lane]   = 0;
        DEST.f16[lane+1] = 0;
DEST[MAXVL-1:VL] = 0;
"""

handler = "x86_vfcmulcph"
jit_lowering = "arm64_neon_fcmla"
fallback = "zig_lane_loop"

neon_register_model = """
x86 xmm/ymm lanes are mapped onto ARM64 v registers; lane width and MAXVL zero/merge rules are preserved by the lowering.
"""

neon_flag_model = """
MXCSR exception/status behavior is preserved through Rosette SIMD floating-point side-effect handlers.
"""

neon_assembly = """
fj mul vD.8h, vN.8h, vM.8h
bl rosette_apply_mxcsr_float_exceptions
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
