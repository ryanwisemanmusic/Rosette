// COMPUTE/SQRTSD.inc
// ARM64/NEON translation mirror generated from ISA/x86/COMPUTE/SQRTSD.inc.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
SQRTSD: preserve the operation and form-specific semantic blocks.
Category: simd_floating_point.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "COMPUTE/SQRTSD.inc"
x86_handler = "x86_sqrtsd"
neon_lowering = "arm64_scalar_fsqrt_d"
lowering_kind = "neon_scalar"

name = "SQRTSD"
category = "simd_floating_point"
feature = "SSE2_AVX_AVX512F"
element_type = "f64"

encodings = [
  { opcode = "F2 0F 51 /r", form = "SQRTSD xmm1, xmm2/m64", op_en = "A", feature = "SSE2", vector_length = 128, encoding = "legacy_sse" },
  { opcode = "VEX.LIG.F2.0F.WIG 51 /r", form = "VSQRTSD xmm1, xmm2, xmm3/m64", op_en = "B", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "EVEX.LLIG.F2.0F.W1 51 /r", form = "VSQRTSD xmm1{k1}{z}, xmm2, xmm3/m64{er}", op_en = "C", feature = "AVX512F", vector_length = 128, encoding = "evex" }
]

element_size = 64
lane_type = "scalar_double_precision_float"

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
DEST.f64[0] = sqrt(DEST.f64[0]);
DEST[MAXVL-1:64] unchanged;
"""

semantic_vex_128 = """
DEST.f64[0] = sqrt(SRC2.f64[0]);
DEST.f64[1] = SRC1.f64[1];
DEST[MAXVL-1:128] = 0;
"""

semantic_evex = """
if k1[0] or no writemask:
    DEST.f64[0] = sqrt(SRC2.f64[0]);
else if zero_masking:
    DEST.f64[0] = 0;
DEST.f64[1] = SRC1.f64[1];
DEST[MAXVL-1:128] = 0;
"""

handler = "x86_sqrtsd"
jit_lowering = "arm64_scalar_fsqrt_d"

neon_register_model = """
x86 scalar double-precision operand is placed in lane 0 of an ARM64 d register; upper lanes preserve the first source.
"""

neon_flag_model = """
MXCSR exception/status behavior is preserved through Rosette SIMD floating-point side-effect handlers.
"""

neon_assembly = """
fsqrt dD, dN
bl rosette_merge_scalar_high_lanes
bl rosette_apply_mxcsr_float_exceptions
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
