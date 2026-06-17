// PREFETCH/PREFETCHW.inc
// ARM64/NEON mirror generated from ISA/x86/PREFETCH/PREFETCHW.inc.
// Source contract: PREFETCHW — cache.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "PREFETCH/PREFETCHW.inc"
x86_handler = "x86_prefetchw"
neon_lowering = "arm64_prefetchw"
lowering_kind = "arm64_documented_contract"

name = "PREFETCHW"
aliases = []
category = "cache"
feature = "prefetchw"
element_type = "i8"
element_size = 8

encodings = [
  { opcode = "0F 0D /1", form = "PREFETCHW m8", op_en = "M", feature = "prefetchw", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  M = []
}

simd_fp_exceptions = []

semantic_general = """
Prefetch data into caches in anticipation of a write (exclusive ownership).
"""

handler = "x86_prefetchw"
jit_lowering = "arm64_prefetchw"
fallback = "zig_prefetchw"

neon_register_model = """
PREFETCHW is a cache hint instruction (no architectural registers modified).
"""

neon_flag_model = """
PREFETCHW does not modify flags.
"""

neon_assembly = """
// NEON lowering: PREFETCHW stub (cache)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
