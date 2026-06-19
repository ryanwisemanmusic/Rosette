// CACHE/CLFLUSH.inc
// ARM64/NEON mirror generated from ISA/x86/CACHE/CLFLUSH.inc.
// Source contract: CLFLUSH — cache_control.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CACHE/CLFLUSH.inc"
x86_handler = "x86_clflush"
neon_lowering = "arm64_clflush"
lowering_kind = "arm64_documented_contract"

name = "CLFLUSH"
aliases = []
category = "cache_control"
feature = "clflush"
element_type = "none"
element_size = 0

encodings = [
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Flush Cache Line.
"""

handler = "x86_clflush"
jit_lowering = "arm64_clflush"
fallback = "zig_clflush"

neon_register_model = """
CLFLUSH is a cache_control instruction.
"""

neon_flag_model = """
CLFLUSH does not modify flags.
"""

neon_assembly = """
// NEON lowering: CLFLUSH stub (cache_control)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

