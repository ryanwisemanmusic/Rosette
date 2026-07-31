// ARITHMETIC/VPADDW.inc
// ARM64/NEON mirror generated from ISA/x86/ARITHMETIC/VPADDW.inc.
// Source contract: VPADDW — simd_arithmetic.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ARITHMETIC/VPADDW.inc"
x86_handler = "x86_vpaddw"
neon_lowering = "arm64_vpaddw"
lowering_kind = "arm64_documented_contract"

name = "VPADDW"
aliases = []
category = "simd_arithmetic"
feature = "avx"
element_type = "i16"
element_size = 16

encodings = [
  { opcode = "VEX.128.66.0F FD /r", form = "VPADDW xmm1, xmm2, xmm3/m128", op_en = "RVM", feature = "avx", vector_length = 0, encoding = "legacy" }
  { opcode = "VEX.256.66.0F FD /r", form = "VPADDW ymm1, ymm2, ymm3/m256", op_en = "RVM", feature = "avx", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Add Packed Words.
"""

handler = "x86_vpaddw"
jit_lowering = "arm64_vpaddw"
fallback = "zig_vpaddw"

neon_register_model = """
VPADDW is a simd_arithmetic instruction.
"""

neon_flag_model = """
VPADDW does not modify flags.
"""

neon_assembly = """
// NEON lowering: VPADDW stub (simd_arithmetic)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

