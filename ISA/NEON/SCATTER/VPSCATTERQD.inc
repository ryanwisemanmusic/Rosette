// SCATTER/VPSCATTERQD.inc
// ARM64/NEON mirror generated from ISA/x86/SCATTER/VPSCATTERQD.inc.
// Source contract: VPSCATTERQD — avx512_scatter.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SCATTER/VPSCATTERQD.inc"
x86_handler = "x86_vpscatterqd"
neon_lowering = "arm64_vpscatterqd"
lowering_kind = "arm64_documented_contract"

name = "VPSCATTERQD"
aliases = []
category = "avx512_scatter"
feature = "avx512f"
element_type = "i32"
element_size = 32

encodings = [
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Scatter Packed Dword with Signed Qword Indices.
"""

handler = "x86_vpscatterqd"
jit_lowering = "arm64_vpscatterqd"
fallback = "zig_vpscatterqd"

neon_register_model = """
VPSCATTERQD is a avx512_scatter instruction.
"""

neon_flag_model = """
VPSCATTERQD does not modify flags.
"""

neon_assembly = """
// NEON lowering: VPSCATTERQD stub (avx512_scatter)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

