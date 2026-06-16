// ANDNOT/VPANDN.inc
// ARM64/NEON mirror generated from ISA/x86/ANDNOT/VPANDN.inc.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ANDNOT/VPANDN.inc"
x86_handler = "x86_vpandn"
neon_lowering = "arm64_vpandn"
lowering_kind = "arm64_documented_contract"

name = "VPANDN"
aliases = []
category = "bitwise"
feature = "AVX"
element_type = "u128_u256"
element_size = 128

encodings = [
  { opcode = "VEX.128.66.0F.WIG DF /r", form = "VPANDN xmm1, xmm2, xmm3/m128", op_en = "B", feature = "AVX", vector_length = 0, encoding = "legacy" },
  { opcode = "VEX.256.66.0F.WIG DF /r", form = "VPANDN ymm1, ymm2, ymm3/m256", op_en = "B", feature = "AVX2", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  B = ["ModRM:reg (w)", "VEX.vvvv (r)", "ModRM:r/m (r)"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
Bitwise AND NOT of packed integers (NOT SRC1 AND SRC2).
"""

handler = "x86_vpandn"
jit_lowering = "arm64_vpandn"
fallback = "zig_vpandn"

neon_register_model = """
VPANDN is a bitwise instruction. ARM64 MVN/BIC available.
"""

neon_flag_model = """
No x86 flags modified by VPANDN.
"""

neon_assembly = """
// NEON lowering: BIC (Vectors) on ARM64
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
