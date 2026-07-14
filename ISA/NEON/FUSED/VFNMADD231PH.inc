// FUSED/VFNMADD231PH.inc
// ARM64/NEON translation mirror generated from ISA/x86/FUSED/VFNMADD231PH.inc.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VFNMADD231PH: preserve the operation and form-specific semantic blocks.
Category: simd_fma_f16.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "FUSED/VFNMADD231PH.inc"
x86_handler = "x86_vfnmadd231ph"
neon_lowering = "arm64_neon_fnmadd_ph"
lowering_kind = "neon_vector"

name = "VFNMADD231PH"
category = "fused"
feature = "AVX512-FP16"
element_type = "f16"

encodings = [
  { opcode = "EVEX.128.66.0F38.W0 66 /r /r", form = "VFNMADD231PH xmm1{k1}{z}, xmm2, xmm3/m128/m16bcst", op_en = "C", feature = "AVX512-FP16" },
  { opcode = "EVEX.256.66.0F38.W0 66 /r /r", form = "VFNMADD231PH ymm1{k1}{z}, ymm2, xmm3/m256/m16bcst", op_en = "C", feature = "AVX512-FP16" },
  { opcode = "EVEX.512.66.0F38.W0 66 /r /r", form = "VFNMADD231PH zmm1{k1}{z}, zmm2, xmm3/m512/m16bcst", op_en = "C", feature = "AVX512-FP16" }
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

semantic_evex = """
for lane in VL:
    if writemask_enabled:
        DEST.f16[lane] = fused_multiply_add_op(SRC1.f16[lane], SRC2.f16[lane], SRC3.f16[lane]);
    else if zero_masking:
        DEST.f16[lane] = 0;
DEST[MAXVL-1:VL] = 0;
"""

handler = "x86_vfnmadd231ph"
jit_lowering = "arm64_neon_fnmadd_ph"
fallback = "zig_lane_loop"

neon_register_model = """
x86 xmm/ymm/zmm lanes are mapped onto ARM64 v registers; lane width and MAXVL zero/merge rules are preserved by the lowering.
"""

neon_flag_model = """
MXCSR exception/status behavior is preserved through Rosette SIMD floating-point side-effect handlers.
"""

neon_assembly = """
// ARM64 NEON: fmla/fmls for FP16 via vD.8h, vN.8h, vM.8h; unrolled for wider VL.
bl rosette_apply_mxcsr_float_exceptions
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
