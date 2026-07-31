// HORIZONTAL/VPHADDD.inc
// ARM64/NEON mirror generated from ISA/x86/HORIZONTAL/VPHADDD.inc.
// Source contract: VPHADDD — simd_horizontal.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "HORIZONTAL/VPHADDD.inc"
x86_handler = "x86_vphaddd"
neon_lowering = "arm64_vphaddd"
lowering_kind = "arm64_documented_contract"

name = "VPHADDD"
aliases = []
category = "simd_horizontal"
feature = "avx"
element_type = "i32"
element_size = 32

encodings = [
  { opcode = "VEX.128.66.0F38 02 /r", form = "VPHADDD xmm1, xmm2, xmm3/m128", op_en = "RVM", feature = "avx", vector_length = 0, encoding = "legacy" }
  { opcode = "VEX.256.66.0F38 02 /r", form = "VPHADDD ymm1, ymm2, ymm3/m256", op_en = "RVM", feature = "avx", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Packed Horizontal Add Dword.
"""

handler = "x86_vphaddd"
jit_lowering = "arm64_vphaddd"
fallback = "zig_vphaddd"

neon_register_model = """
VPHADDD is a simd_horizontal instruction.
"""

neon_flag_model = """
VPHADDD does not modify flags.
"""

neon_assembly = """
// NEON lowering: VPHADDD stub (simd_horizontal)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

