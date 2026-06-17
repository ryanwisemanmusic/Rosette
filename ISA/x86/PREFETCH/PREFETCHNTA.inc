// PREFETCH/PREFETCHNTA.inc
// Source contract: PREFETCHNTA — cache.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "PREFETCH/PREFETCHNTA.inc"
x86_handler = "x86_prefetchnta"
neon_lowering = "arm64_prefetchnta"
lowering_kind = "arm64_documented_contract"

name = "PREFETCHNTA"
aliases = []
category = "cache"
feature = "sse"
element_type = "i8"
element_size = 8

encodings = [
  { opcode = "0F 18 /0", form = "PREFETCHNTA m8", op_en = "M", feature = "sse", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  M = []
}

simd_fp_exceptions = []

semantic_general = """
Prefetch data into non-temporal cache (NTA hint).
"""

handler = "x86_prefetchnta"
jit_lowering = "arm64_prefetchnta"
fallback = "zig_prefetchnta"

neon_register_model = """
PREFETCHNTA is a cache hint instruction (no architectural registers modified).
"""

neon_flag_model = """
PREFETCHNTA does not modify flags.
"""

neon_assembly = """
// NEON lowering: PREFETCHNTA stub (cache)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
