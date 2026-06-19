// SCAN/SCASQ.inc
// ARM64/NEON mirror generated from ISA/x86/SCAN/SCASQ.inc.
// Source contract: SCASQ — string_op.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SCAN/SCASQ.inc"
x86_handler = "x86_scasq"
neon_lowering = "arm64_scasq"
lowering_kind = "arm64_documented_contract"

name = "SCASQ"
aliases = []
category = "string_op"
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
Scan String Quadword.
"""

handler = "x86_scasq"
jit_lowering = "arm64_scasq"
fallback = "zig_scasq"

neon_register_model = """
SCASQ is a string_op instruction.
"""

neon_flag_model = """
SCASQ does not modify flags.
"""

neon_assembly = """
// NEON lowering: SCASQ stub (string_op)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

