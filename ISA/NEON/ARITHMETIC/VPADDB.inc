// ARITHMETIC/VPADDB.inc
// ARM64/NEON mirror generated from ISA/x86/ARITHMETIC/VPADDB.inc.
// Source contract: VPADDB — simd_arithmetic.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ARITHMETIC/VPADDB.inc"
x86_handler = "x86_vpaddb"
neon_lowering = "arm64_vpaddb"
lowering_kind = "arm64_documented_contract"

name = "VPADDB"
aliases = []
category = "simd_arithmetic"
feature = "avx"
element_type = "i8"
element_size = 8

encodings = [
  { opcode = "VEX.128.66.0F FC /r", form = "VPADDB xmm1, xmm2, xmm3/m128", op_en = "RVM", feature = "avx", vector_length = 0, encoding = "legacy" }
  { opcode = "VEX.256.66.0F FC /r", form = "VPADDB ymm1, ymm2, ymm3/m256", op_en = "RVM", feature = "avx", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Add Packed Bytes.
"""

handler = "x86_vpaddb"
jit_lowering = "arm64_vpaddb"
fallback = "zig_vpaddb"

neon_register_model = """
VPADDB is a simd_arithmetic instruction.
"""

neon_flag_model = """
VPADDB does not modify flags.
"""

neon_assembly = """
// NEON lowering: VPADDB stub (simd_arithmetic)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

