// MAKE/ENTER.inc
// ARM64/NEON mirror generated from ISA/x86/MAKE/ENTER.inc.
// Source contract: ENTER — stack_control.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "MAKE/ENTER.inc"
x86_handler = "x86_enter"
neon_lowering = "arm64_enter"
lowering_kind = "arm64_documented_contract"

name = "ENTER"
aliases = []
category = "stack_control"
feature = "general"
element_type = "none"
element_size = 0

encodings = [
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Make Stack Frame for Procedure Parameters.
"""

handler = "x86_enter"
jit_lowering = "arm64_enter"
fallback = "zig_enter"

neon_register_model = """
ENTER is a stack_control instruction.
"""

neon_flag_model = """
ENTER does not modify flags.
"""

neon_assembly = """
// NEON lowering: ENTER stub (stack_control)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

