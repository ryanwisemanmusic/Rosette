// REPEAT/REPE.inc
// Source contract: REPE — prefix.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "REPEAT/REPE.inc"
x86_handler = "x86_repe"
neon_lowering = "arm64_repe"
lowering_kind = "arm64_documented_contract"

name = "REPE"
aliases = []
category = "prefix"
feature = "general"
element_type = "none"
element_size = 0

encodings = [
  { opcode = "F3", form = "REPE", op_en = "ZO", feature = "general", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Repeat While Equal Prefix.
"""

handler = "x86_repe"
jit_lowering = "arm64_repe"
fallback = "zig_repe"

neon_register_model = """
REPE is a prefix instruction.
"""

neon_flag_model = """
REPE does not modify flags.
"""

neon_assembly = """
// NEON lowering: REPE stub (prefix)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

