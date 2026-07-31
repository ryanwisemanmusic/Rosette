// FUSED/VFMADDSUB213PS.inc
// ARM64/NEON translation mirror generated from ISA/x86/FUSED/VFMADDSUB213PS.inc.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VFMADDSUB213PS: preserve the operation and form-specific semantic blocks.
Category: simd_fma_f32.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "FUSED/VFMADDSUB213PS.inc"
x86_handler = "x86_vfmaddsub213ps"
neon_lowering = "arm64_vfmaddsub213ps"
lowering_kind = "neon_vector"

name = "VFMADDSUB213PS"
category = "fused"
feature = "FMA"
element_type = "f32"

encodings = [
  { opcode = "VEX.128.66.0F38.W0 66 /r /r", form = "VFMADDSUB213PS xmm1, xmm2, xmm3/m128", op_en = "C", feature = "FMA" },
  { opcode = "VEX.256.66.0F38.W0 66 /r /r", form = "VFMADDSUB213PS ymm1, ymm2, ymm3/m256", op_en = "C", feature = "FMA" },
  { opcode = "EVEX.128.66.0F38.W0 66 /r /r", form = "VFMADDSUB213PS xmm1{k1}{z}, xmm2, xmm3/m128/m32bcst", op_en = "C", feature = "AVX512F" },
  { opcode = "EVEX.256.66.0F38.W0 66 /r /r", form = "VFMADDSUB213PS ymm1{k1}{z}, ymm2, xmm3/m256/m32bcst", op_en = "C", feature = "AVX512F" },
  { opcode = "EVEX.512.66.0F38.W0 66 /r /r", form = "VFMADDSUB213PS zmm1{k1}{z}, zmm2, xmm3/m512/m32bcst", op_en = "C", feature = "AVX512F" }
]

element_size = 32
lane_type = "single_precision_float"

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

semantic_vex_128 = """
DEST.f32[0] = fused_multiply_add_op(SRC1.f32[0], SRC2.f32[0], SRC3.f32[0]);
DEST.f32[1] = fused_multiply_add_op(SRC1.f32[1], SRC2.f32[1], SRC3.f32[1]);
DEST.f32[2] = fused_multiply_add_op(SRC1.f32[2], SRC2.f32[2], SRC3.f32[2]);
DEST.f32[3] = fused_multiply_add_op(SRC1.f32[3], SRC2.f32[3], SRC3.f32[3]);
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
for i in 0..7:
    DEST.f32[i] = fused_multiply_add_op(SRC1.f32[i], SRC2.f32[i], SRC3.f32[i]);
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
for lane in VL:
    if writemask_enabled:
        DEST.f32[lane] = fused_multiply_add_op(SRC1.f32[lane], SRC2.f32[lane], SRC3.f32[lane]);
    else if zero_masking:
        DEST.f32[lane] = 0;
DEST[MAXVL-1:VL] = 0;
"""

handler = "x86_vfmaddsub213ps"
jit_lowering = "arm64_neon_fmaddsub_ps"
fallback = "zig_lane_loop"

neon_register_model = """
x86 xmm/ymm/zmm lanes are mapped onto ARM64 v registers; lane width and MAXVL zero/merge rules are preserved by the lowering.
"""

neon_flag_model = """
MXCSR exception/status behavior is preserved through Rosette SIMD floating-point side-effect handlers.
"""

neon_assembly = """
// ARM64 NEON: fmadd/fmsub vD.4s, vN.4s, vM.4s, vA.4s for 128-bit; unrolled for wider VL.
bl rosette_apply_mxcsr_float_exceptions
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
