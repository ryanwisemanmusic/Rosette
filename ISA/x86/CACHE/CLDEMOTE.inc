// CACHE/CLDEMOTE.inc
// Source contract: CLDEMOTE — cache_control.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CACHE/CLDEMOTE.inc"
x86_handler = "x86_cldemote"
neon_lowering = "arm64_cldemote"
lowering_kind = "arm64_documented_contract"

name = "CLDEMOTE"
aliases = []
category = "cache_control"
feature = "cldemote"
element_type = "none"
element_size = 0

encodings = [
  { opcode = "NP 0F 1C /0", form = "CLDEMOTE m8", op_en = "A", feature = "cldemote", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Cache Line Demote.
"""

handler = "x86_cldemote"
jit_lowering = "arm64_cldemote"
fallback = "zig_cldemote"

neon_register_model = """
CLDEMOTE is a cache_control instruction.
"""

neon_flag_model = """
CLDEMOTE does not modify flags.
"""

neon_assembly = """
// NEON lowering: CLDEMOTE stub (cache_control)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

