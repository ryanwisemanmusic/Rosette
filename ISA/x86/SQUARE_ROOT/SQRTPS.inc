// SQUARE_ROOT/SQRTPS.inc
// Source contract: SQRTPS — simd_float_sqrt.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SQUARE_ROOT/SQRTPS.inc"
x86_handler = "x86_sqrtps"
neon_lowering = "arm64_sqrtps"
lowering_kind = "arm64_documented_contract"

name = "SQRTPS"
aliases = []
category = "simd_float_sqrt"
feature = "sse"
element_type = "f32"
element_size = 32

encodings = [
  { opcode = "NP 0F 51 /r", form = "SQRTPS xmm1, xmm2/m128", op_en = "A", feature = "sse", vector_length = 0, encoding = "legacy" }
  { opcode = "VEX.128.0F.WIG 51 /r", form = "VSQRTPS xmm1, xmm2/m128", op_en = "A", feature = "avx", vector_length = 0, encoding = "legacy" }
  { opcode = "VEX.256.0F.WIG 51 /r", form = "VSQRTPS ymm1, ymm2/m256", op_en = "A", feature = "avx", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Square Root of Single Precision Floating-Point Values.
"""

handler = "x86_sqrtps"
jit_lowering = "arm64_sqrtps"
fallback = "zig_sqrtps"

neon_register_model = """
SQRTPS is a simd_float_sqrt instruction.
"""

neon_flag_model = """
SQRTPS does not modify flags.
"""

neon_assembly = """
// NEON lowering: SQRTPS stub (simd_float_sqrt)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

