// PREFETCH/PREFETCHT0.inc
// ARM64/NEON mirror generated from ISA/x86/PREFETCH/PREFETCHT0.inc.
// Source contract: PREFETCHT0 — cache.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "PREFETCH/PREFETCHT0.inc"
x86_handler = "x86_prefetcht0"
neon_lowering = "arm64_prefetcht0"
lowering_kind = "arm64_documented_contract"

name = "PREFETCHT0"
aliases = []
category = "cache"
feature = "sse"
element_type = "i8"
element_size = 8

encodings = [
  { opcode = "0F 18 /1", form = "PREFETCHT0 m8", op_en = "M", feature = "sse", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  M = []
}

simd_fp_exceptions = []

semantic_general = """
Prefetch data into all cache levels (T0 hint).
"""

handler = "x86_prefetcht0"
jit_lowering = "arm64_prefetcht0"
fallback = "zig_prefetcht0"

neon_register_model = """
PREFETCHT0 is a cache hint instruction (no architectural registers modified).
"""

neon_flag_model = """
PREFETCHT0 does not modify flags.
"""

neon_assembly = """
// NEON lowering: PREFETCHT0 stub (cache)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
