// CACHE/CLWB.inc
// ARM64/NEON mirror generated from ISA/x86/CACHE/CLWB.inc.
// Source contract: CLWB — cache_control.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CACHE/CLWB.inc"
x86_handler = "x86_clwb"
neon_lowering = "arm64_clwb"
lowering_kind = "arm64_documented_contract"

name = "CLWB"
aliases = []
category = "cache_control"
feature = "clwb"
element_type = "none"
element_size = 0

encodings = [
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Cache Line Write Back.
"""

handler = "x86_clwb"
jit_lowering = "arm64_clwb"
fallback = "zig_clwb"

neon_register_model = """
CLWB is a cache_control instruction.
"""

neon_flag_model = """
CLWB does not modify flags.
"""

neon_assembly = """
// NEON lowering: CLWB stub (cache_control)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

