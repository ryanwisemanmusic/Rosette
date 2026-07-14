// FUSED/VFMADD231PD.inc
// ARM64/NEON translation mirror generated from ISA/x86/FUSED/VFMADD231PD.inc.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VFMADD231PD: preserve the operation and form-specific semantic blocks.
Category: simd_fma_f64.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "FUSED/VFMADD231PD.inc"
x86_handler = "x86_vfmadd231pd"
neon_lowering = "arm64_neon_fmadd_pd"
lowering_kind = "neon_vector"

name = "VFMADD231PD"
category = "fused"
feature = "FMA"
element_type = "f64"

encodings = [
  { opcode = "VEX.128.66.0F38.W1 66 /r /r", form = "VFMADD231PD xmm1, xmm2, xmm3/m128", op_en = "C", feature = "FMA" },
  { opcode = "VEX.256.66.0F38.W1 66 /r /r", form = "VFMADD231PD ymm1, ymm2, ymm3/m256", op_en = "C", feature = "FMA" },
  { opcode = "EVEX.128.66.0F38.W1 66 /r /r", form = "VFMADD231PD xmm1{k1}{z}, xmm2, xmm3/m128/m64bcst", op_en = "C", feature = "AVX512F" },
  { opcode = "EVEX.256.66.0F38.W1 66 /r /r", form = "VFMADD231PD ymm1{k1}{z}, ymm2, xmm3/m256/m64bcst", op_en = "C", feature = "AVX512F" },
  { opcode = "EVEX.512.66.0F38.W1 66 /r /r", form = "VFMADD231PD zmm1{k1}{z}, zmm2, xmm3/m512/m64bcst", op_en = "C", feature = "AVX512F" }
]

element_size = 64
lane_type = "double_precision_float"

lanes = {
  xmm = 2,
  ymm = 4,
  zmm = 8
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
DEST.f64[0] = fused_multiply_add_op(SRC1.f64[0], SRC2.f64[0], SRC3.f64[0]);
DEST.f64[1] = fused_multiply_add_op(SRC1.f64[1], SRC2.f64[1], SRC3.f64[1]);
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
for i in 0..3:
    DEST.f64[i] = fused_multiply_add_op(SRC1.f64[i], SRC2.f64[i], SRC3.f64[i]);
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
for lane in VL:
    if writemask_enabled:
        DEST.f64[lane] = fused_multiply_add_op(SRC1.f64[lane], SRC2.f64[lane], SRC3.f64[lane]);
    else if zero_masking:
        DEST.f64[lane] = 0;
DEST[MAXVL-1:VL] = 0;
"""

handler = "x86_vfmadd231pd"
jit_lowering = "arm64_neon_fmadd_pd"
fallback = "zig_lane_loop"

neon_register_model = """
x86 xmm/ymm/zmm lanes are mapped onto ARM64 v registers; lane width and MAXVL zero/merge rules are preserved by the lowering.
"""

neon_flag_model = """
MXCSR exception/status behavior is preserved through Rosette SIMD floating-point side-effect handlers.
"""

neon_assembly = """
// ARM64 NEON: fmadd/fmsub vD.2d, vN.2d, vM.2d, vA.2d for 128-bit; unrolled for wider VL.
bl rosette_apply_mxcsr_float_exceptions
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
