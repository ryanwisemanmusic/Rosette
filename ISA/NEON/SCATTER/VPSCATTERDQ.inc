// SCATTER/VPSCATTERDQ.inc
// ARM64/NEON mirror generated from ISA/x86/SCATTER/VPSCATTERDQ.inc.
// Source contract: VPSCATTERDQ — avx512_scatter.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SCATTER/VPSCATTERDQ.inc"
x86_handler = "x86_vpscatterdq"
neon_lowering = "arm64_vpscatterdq"
lowering_kind = "arm64_documented_contract"

name = "VPSCATTERDQ"
aliases = []
category = "avx512_scatter"
feature = "avx512f"
element_type = "i64"
element_size = 64

encodings = [
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Scatter Packed Qword with Signed Dword Indices.
"""

handler = "x86_vpscatterdq"
jit_lowering = "arm64_vpscatterdq"
fallback = "zig_vpscatterdq"

neon_register_model = """
VPSCATTERDQ is a avx512_scatter instruction.
"""

neon_flag_model = """
VPSCATTERDQ does not modify flags.
"""

neon_assembly = """
// NEON lowering: VPSCATTERDQ stub (avx512_scatter)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

