// SCATTER/VSCATTERQPD.inc
// ARM64/NEON mirror generated from ISA/x86/SCATTER/VSCATTERQPD.inc.
// Source contract: VSCATTERQPD — avx512_scatter.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SCATTER/VSCATTERQPD.inc"
x86_handler = "x86_vscatterqpd"
neon_lowering = "arm64_vscatterqpd"
lowering_kind = "arm64_documented_contract"

name = "VSCATTERQPD"
aliases = []
category = "avx512_scatter"
feature = "avx512f"
element_type = "f64"
element_size = 64

encodings = [
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Scatter Packed Double with Signed Qword Indices.
"""

handler = "x86_vscatterqpd"
jit_lowering = "arm64_vscatterqpd"
fallback = "zig_vscatterqpd"

neon_register_model = """
VSCATTERQPD is a avx512_scatter instruction.
"""

neon_flag_model = """
VSCATTERQPD does not modify flags.
"""

neon_assembly = """
// NEON lowering: VSCATTERQPD stub (avx512_scatter)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

