// ARITHMETIC/VPADDD.inc
// Source contract: VPADDD — simd_arithmetic.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ARITHMETIC/VPADDD.inc"
x86_handler = "x86_vpaddd"
neon_lowering = "arm64_vpaddd"
lowering_kind = "arm64_documented_contract"

name = "VPADDD"
aliases = []
category = "simd_arithmetic"
feature = "avx"
element_type = "i32"
element_size = 32

encodings = [
  { opcode = "VEX.128.66.0F FE /r", form = "VPADDD xmm1, xmm2, xmm3/m128", op_en = "RVM", feature = "avx", vector_length = 0, encoding = "legacy" }
  { opcode = "VEX.256.66.0F FE /r", form = "VPADDD ymm1, ymm2, ymm3/m256", op_en = "RVM", feature = "avx", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}
simd_fp_exceptions = []

semantic_general = """
Add Packed Doublewords.
"""

handler = "x86_vpaddd"
jit_lowering = "arm64_vpaddd"
fallback = "zig_vpaddd"

neon_register_model = """
VPADDD is a simd_arithmetic instruction.
"""

neon_flag_model = """
VPADDD does not modify flags.
"""

neon_assembly = """
// NEON lowering: VPADDD stub (simd_arithmetic)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

