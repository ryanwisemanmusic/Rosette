// FUSED/VFMSUB231SH.inc
// ARM64/NEON translation mirror generated from ISA/x86/FUSED/VFMSUB231SH.inc.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VFMSUB231SH: preserve the operation and form-specific semantic blocks.
Category: simd_scalar_fma_f16.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "FUSED/VFMSUB231SH.inc"
x86_handler = "x86_vfmsub231sh"
neon_lowering = "arm64_scalar_fmsub_h"
lowering_kind = "neon_scalar"

name = "VFMSUB231SH"
category = "fused"
feature = "AVX512-FP16"
element_type = "f16"

encodings = [
  { opcode = "EVEX.LLIG.66.0F38.W0 66 /r /r", form = "VFMSUB231SH xmm1{k1}{z}, xmm2, xmm3/m16{er}", op_en = "C", feature = "AVX512-FP16" }
]

element_size = 16
lane_type = "scalar_half_precision_float"

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
if k1[0] or no writemask:
    DEST.f16[0] = fused_multiply_add_op(SRC1.f16[0], SRC2.f16[0], SRC3.f16[0]);
else if zero_masking:
    DEST.f16[0] = 0;
DEST.f16[1..7] = SRC1.f16[1..7];
DEST[MAXVL-1:128] = 0;
"""

handler = "x86_vfmsub231sh"
jit_lowering = "arm64_scalar_fmsub_h"

neon_register_model = """
x86 scalar operand is placed in lane 0 of an ARM64 v register; upper lanes preserve the first source.
"""

neon_flag_model = """
MXCSR exception/status behavior is preserved through Rosette SIMD floating-point side-effect handlers.
"""

neon_assembly = """
// ARM64: fmadd hD, hN, hM, hA (or fmsub/fnmadd variant)
bl rosette_merge_scalar_high_lanes
bl rosette_apply_mxcsr_float_exceptions
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
