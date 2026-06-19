// CACHE/CLFLUSHOPT.inc
// ARM64/NEON mirror generated from ISA/x86/CACHE/CLFLUSHOPT.inc.
// Source contract: CLFLUSHOPT — cache_control.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CACHE/CLFLUSHOPT.inc"
x86_handler = "x86_clflushopt"
neon_lowering = "arm64_clflushopt"
lowering_kind = "arm64_documented_contract"

name = "CLFLUSHOPT"
aliases = []
category = "cache_control"
feature = "clflushopt"
element_type = "none"
element_size = 0

encodings = [
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Flush Cache Line Optimized.
"""

handler = "x86_clflushopt"
jit_lowering = "arm64_clflushopt"
fallback = "zig_clflushopt"

neon_register_model = """
CLFLUSHOPT is a cache_control instruction.
"""

neon_flag_model = """
CLFLUSHOPT does not modify flags.
"""

neon_assembly = """
// NEON lowering: CLFLUSHOPT stub (cache_control)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

