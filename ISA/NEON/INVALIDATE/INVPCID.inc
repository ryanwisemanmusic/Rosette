// INVALIDATE/INVPCID.inc
// ARM64/NEON mirror generated from ISA/x86/INVALIDATE/INVPCID.inc.
// Source contract: INVPCID — tlb_control.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INVALIDATE/INVPCID.inc"
x86_handler = "x86_invpcid"
neon_lowering = "arm64_invpcid"
lowering_kind = "arm64_documented_contract"

name = "INVPCID"
aliases = []
category = "tlb_control"
feature = "invpcid"
element_type = "none"
element_size = 0

encodings = [
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Invalidate Process-Context Identifier.
"""

handler = "x86_invpcid"
jit_lowering = "arm64_invpcid"
fallback = "zig_invpcid"

neon_register_model = """
INVPCID is a tlb_control instruction.
"""

neon_flag_model = """
INVPCID does not modify flags.
"""

neon_assembly = """
// NEON lowering: INVPCID stub (tlb_control)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

