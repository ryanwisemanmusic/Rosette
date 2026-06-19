// SCAN/SCAS.inc
// ARM64/NEON mirror generated from ISA/x86/SCAN/SCAS.inc.
// Source contract: SCAS — string_op.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SCAN/SCAS.inc"
x86_handler = "x86_scas"
neon_lowering = "arm64_scas"
lowering_kind = "arm64_documented_contract"

name = "SCAS"
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
Scan String.
"""

handler = "x86_scas"
jit_lowering = "arm64_scas"
fallback = "zig_scas"

neon_register_model = """
SCAS is a string_op instruction.
"""

neon_flag_model = """
SCAS does not modify flags.
"""

neon_assembly = """
// NEON lowering: SCAS stub (string_op)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

