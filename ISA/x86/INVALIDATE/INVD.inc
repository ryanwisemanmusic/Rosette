// INVALIDATE/INVD.inc
// Source contract: INVD — cache_control.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INVALIDATE/INVD.inc"
x86_handler = "x86_invd"
neon_lowering = "arm64_invd"
lowering_kind = "arm64_documented_contract"

name = "INVD"
aliases = []
category = "cache_control"
feature = "general"
element_type = "none"
element_size = 0

encodings = [
  { opcode = "0F 08", form = "INVD", op_en = "ZO", feature = "general", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Invalidate Internal Caches.
"""

handler = "x86_invd"
jit_lowering = "arm64_invd"
fallback = "zig_invd"

neon_register_model = """
INVD is a cache_control instruction.
"""

neon_flag_model = """
INVD does not modify flags.
"""

neon_assembly = """
// NEON lowering: INVD stub (cache_control)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

