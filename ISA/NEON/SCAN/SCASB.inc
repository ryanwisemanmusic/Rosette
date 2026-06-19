// SCAN/SCASB.inc
// ARM64/NEON mirror generated from ISA/x86/SCAN/SCASB.inc.
// Source contract: SCASB — string_op.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SCAN/SCASB.inc"
x86_handler = "x86_scasb"
neon_lowering = "arm64_scasb"
lowering_kind = "arm64_documented_contract"

name = "SCASB"
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
Scan String Byte.
"""

handler = "x86_scasb"
jit_lowering = "arm64_scasb"
fallback = "zig_scasb"

neon_register_model = """
SCASB is a string_op instruction.
"""

neon_flag_model = """
SCASB does not modify flags.
"""

neon_assembly = """
// NEON lowering: SCASB stub (string_op)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

