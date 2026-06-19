// SCATTER/VSCATTERQPS.inc
// ARM64/NEON mirror generated from ISA/x86/SCATTER/VSCATTERQPS.inc.
// Source contract: VSCATTERQPS — avx512_scatter.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SCATTER/VSCATTERQPS.inc"
x86_handler = "x86_vscatterqps"
neon_lowering = "arm64_vscatterqps"
lowering_kind = "arm64_documented_contract"

name = "VSCATTERQPS"
aliases = []
category = "avx512_scatter"
feature = "avx512f"
element_type = "f32"
element_size = 32

encodings = [
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Scatter Packed Single with Signed Qword Indices.
"""

handler = "x86_vscatterqps"
jit_lowering = "arm64_vscatterqps"
fallback = "zig_vscatterqps"

neon_register_model = """
VSCATTERQPS is a avx512_scatter instruction.
"""

neon_flag_model = """
VSCATTERQPS does not modify flags.
"""

neon_assembly = """
// NEON lowering: VSCATTERQPS stub (avx512_scatter)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

