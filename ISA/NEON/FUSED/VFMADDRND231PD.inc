// FUSED/VFMADDRND231PD.inc
// ARM64/NEON translation mirror generated from ISA/x86/FUSED/VFMADDRND231PD.inc.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VFMADDRND231PD: preserve the operation and form-specific semantic blocks.
Category: simd_fma_f64_rounding.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "FUSED/VFMADDRND231PD.inc"
x86_handler = "x86_vfmaddrnd231pd"
neon_lowering = "arm64_neon_fmadd_round_pd"
lowering_kind = "neon_vector"

name = "VFMADDRND231PD"
category = "fused"
feature = "AVX512F"
element_type = "f64"

encodings = [
  { opcode = "EVEX.128.66.0F38.W1 66 /r /r", form = "VFMADDRND231PD xmm1{k1}{z}, xmm2, xmm3/m128/m64bcst", op_en = "C", feature = "AVX512F" },
  { opcode = "EVEX.256.66.0F38.W1 66 /r /r", form = "VFMADDRND231PD ymm1{k1}{z}, ymm2, xmm3/m256/m64bcst", op_en = "C", feature = "AVX512F" },
  { opcode = "EVEX.512.66.0F38.W1 66 /r /r", form = "VFMADDRND231PD zmm1{k1}{z}, zmm2, xmm3/m512/m64bcst", op_en = "C", feature = "AVX512F" }
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

semantic_evex = """
for lane in VL:
    if writemask_enabled:
        DEST.f64[lane] = rounding_fmadd_op(SRC1.f64[lane], SRC2.f64[lane], SRC3.f64[lane]);
    else if zero_masking:
        DEST.f64[lane] = 0;
DEST[MAXVL-1:VL] = 0;
// The rounding mode is specified via EVEX.b (static rounding) or MXCSR.RC.
"""

handler = "x86_vfmaddrnd231pd"
jit_lowering = "arm64_neon_fmadd_round_pd"
fallback = "zig_lane_loop"

neon_register_model = """
x86 xmm/ymm/zmm lanes are mapped onto ARM64 v registers; lane width and MAXVL zero/merge rules are preserved by the lowering.
"""

neon_flag_model = """
MXCSR exception/status behavior is preserved through Rosette SIMD floating-point side-effect handlers.
"""

neon_assembly = """
// ARM64 NEON: fmadd with explicit rounding via frintp/frintm/frintn + fmadd sequence.
bl rosette_apply_mxcsr_float_exceptions
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
