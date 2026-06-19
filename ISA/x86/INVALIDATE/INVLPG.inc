// INVALIDATE/INVLPG.inc
// Source contract: INVLPG — tlb_control.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INVALIDATE/INVLPG.inc"
x86_handler = "x86_invlpg"
neon_lowering = "arm64_invlpg"
lowering_kind = "arm64_documented_contract"

name = "INVLPG"
aliases = []
category = "tlb_control"
feature = "general"
element_type = "none"
element_size = 0

encodings = [
  { opcode = "0F 01/7", form = "INVLPG m", op_en = "M", feature = "general", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Invalidate TLB Entries.
"""

handler = "x86_invlpg"
jit_lowering = "arm64_invlpg"
fallback = "zig_invlpg"

neon_register_model = """
INVLPG is a tlb_control instruction.
"""

neon_flag_model = """
INVLPG does not modify flags.
"""

neon_assembly = """
// NEON lowering: INVLPG stub (tlb_control)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

