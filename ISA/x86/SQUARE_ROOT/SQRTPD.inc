// SQUARE_ROOT/SQRTPD.inc
// Source contract: SQRTPD — simd_float_sqrt.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SQUARE_ROOT/SQRTPD.inc"
x86_handler = "x86_sqrtpd"
neon_lowering = "arm64_sqrtpd"
lowering_kind = "arm64_documented_contract"

name = "SQRTPD"
aliases = []
category = "simd_float_sqrt"
feature = "sse2"
element_type = "f64"
element_size = 64

encodings = [
  { opcode = "66 0F 51 /r", form = "SQRTPD xmm1, xmm2/m128", op_en = "A", feature = "sse2", vector_length = 0, encoding = "legacy" }
  { opcode = "VEX.128.66.0F.WIG 51 /r", form = "VSQRTPD xmm1, xmm2/m128", op_en = "A", feature = "avx", vector_length = 0, encoding = "legacy" }
  { opcode = "VEX.256.66.0F.WIG 51 /r", form = "VSQRTPD ymm1, ymm2/m256", op_en = "A", feature = "avx", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Square Root of Double Precision Floating-Point Values.
"""

handler = "x86_sqrtpd"
jit_lowering = "arm64_sqrtpd"
fallback = "zig_sqrtpd"

neon_register_model = """
SQRTPD is a simd_float_sqrt instruction.
"""

neon_flag_model = """
SQRTPD does not modify flags.
"""

neon_assembly = """
// NEON lowering: SQRTPD stub (simd_float_sqrt)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

