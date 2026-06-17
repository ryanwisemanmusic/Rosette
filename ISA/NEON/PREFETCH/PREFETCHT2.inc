// PREFETCH/PREFETCHT2.inc
// ARM64/NEON mirror generated from ISA/x86/PREFETCH/PREFETCHT2.inc.
// Source contract: PREFETCHT2 — cache.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "PREFETCH/PREFETCHT2.inc"
x86_handler = "x86_prefetcht2"
neon_lowering = "arm64_prefetcht2"
lowering_kind = "arm64_documented_contract"

name = "PREFETCHT2"
aliases = []
category = "cache"
feature = "sse"
element_type = "i8"
element_size = 8

encodings = [
  { opcode = "0F 18 /3", form = "PREFETCHT2 m8", op_en = "M", feature = "sse", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  M = []
}

simd_fp_exceptions = []

semantic_general = """
Prefetch data into L3 and higher cache levels (T2 hint).
"""

handler = "x86_prefetcht2"
jit_lowering = "arm64_prefetcht2"
fallback = "zig_prefetcht2"

neon_register_model = """
PREFETCHT2 is a cache hint instruction (no architectural registers modified).
"""

neon_flag_model = """
PREFETCHT2 does not modify flags.
"""

neon_assembly = """
// NEON lowering: PREFETCHT2 stub (cache)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
