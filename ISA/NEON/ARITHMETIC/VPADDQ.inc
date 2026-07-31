// ARITHMETIC/VPADDQ.inc
// ARM64/NEON mirror generated from ISA/x86/ARITHMETIC/VPADDQ.inc.
// Source contract: VPADDQ — simd_arithmetic.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ARITHMETIC/VPADDQ.inc"
x86_handler = "x86_vpaddq"
neon_lowering = "arm64_vpaddq"
lowering_kind = "arm64_documented_contract"

name = "VPADDQ"
aliases = []
category = "simd_arithmetic"
feature = "avx"
element_type = "i64"
element_size = 64

encodings = [
  { opcode = "VEX.128.66.0F D4 /r", form = "VPADDQ xmm1, xmm2, xmm3/m128", op_en = "RVM", feature = "avx", vector_length = 0, encoding = "legacy" }
  { opcode = "VEX.256.66.0F D4 /r", form = "VPADDQ ymm1, ymm2, ymm3/m256", op_en = "RVM", feature = "avx", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Add Packed Quadwords.
"""

handler = "x86_vpaddq"
jit_lowering = "arm64_vpaddq"
fallback = "zig_vpaddq"

neon_register_model = """
VPADDQ is a simd_arithmetic instruction.
"""

neon_flag_model = """
VPADDQ does not modify flags.
"""

neon_assembly = """
// NEON lowering: VPADDQ stub (simd_arithmetic)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

