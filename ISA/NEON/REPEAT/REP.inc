// REPEAT/REP.inc
// ARM64/NEON mirror generated from ISA/x86/REPEAT/REP.inc.
// Source contract: REP — prefix.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "REPEAT/REP.inc"
x86_handler = "x86_rep"
neon_lowering = "arm64_rep"
lowering_kind = "arm64_documented_contract"

name = "REP"
aliases = []
category = "prefix"
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
Repeat String Operation Prefix.
"""

handler = "x86_rep"
jit_lowering = "arm64_rep"
fallback = "zig_rep"

neon_register_model = """
REP is a prefix instruction.
"""

neon_flag_model = """
REP does not modify flags.
"""

neon_assembly = """
// NEON lowering: REP stub (prefix)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

