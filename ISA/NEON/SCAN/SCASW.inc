// SCAN/SCASW.inc
// ARM64/NEON mirror generated from ISA/x86/SCAN/SCASW.inc.
// Source contract: SCASW — string_op.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SCAN/SCASW.inc"
x86_handler = "x86_scasw"
neon_lowering = "arm64_scasw"
lowering_kind = "arm64_documented_contract"

name = "SCASW"
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
Scan String Word.
"""

handler = "x86_scasw"
jit_lowering = "arm64_scasw"
fallback = "zig_scasw"

neon_register_model = """
SCASW is a string_op instruction.
"""

neon_flag_model = """
SCASW does not modify flags.
"""

neon_assembly = """
// NEON lowering: SCASW stub (string_op)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

