// MEMORY/MFENCE.inc
// Source contract: MFENCE — Memory Fence.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "MEMORY/MFENCE.inc"
x86_handler = "x86_mfence"
neon_lowering = "arm64_mfence"
lowering_kind = "arm64_documented_contract"

name = "MFENCE"
aliases = []
category = "memory_fence"
feature = "sse2"

encodings = [
  { opcode = "NP 0F AE F0", form = "MFENCE", op_en = "ZO", feature = "sse2", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = ["N/A", "N/A", "N/A", "N/A"]
}

lanes = { scalar = 1 }
flags_written = []
floating_point_exceptions = []
other_exceptions = [
  "#UD If CPUID.01H:EDX.SSE2[bit 26] = 0.",
  "#UD If the LOCK prefix is used."
]

semantic_general = """
Performs a serializing operation on all load-from-memory and store-to-memory instructions that were issued prior the MFENCE instruction.
Guarantees that every load and store instruction that precedes MFENCE in program order becomes globally visible before any load or store instruction that follows MFENCE.
"""

handler = "x86_mfence"
jit_lowering = "arm64_mfence"
fallback = "zig_mfence"

neon_register_model = """
MFENCE is an x86 memory fencing instruction. No ARM64 NEON equivalent; handled via documented contract.
"""

neon_flag_model = """
None.
"""

neon_assembly = """
// NEON lowering: MFENCE stub (memory fence)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
