// REPEAT/REPNE.inc
// Source contract: REPNE — prefix.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "REPEAT/REPNE.inc"
x86_handler = "x86_repne"
neon_lowering = "arm64_repne"
lowering_kind = "arm64_documented_contract"

name = "REPNE"
aliases = []
category = "prefix"
feature = "general"
element_type = "none"
element_size = 0

encodings = [
  { opcode = "F2", form = "REPNE", op_en = "ZO", feature = "general", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Repeat While Not Equal Prefix.
"""

handler = "x86_repne"
jit_lowering = "arm64_repne"
fallback = "zig_repne"

neon_register_model = """
REPNE is a prefix instruction.
"""

neon_flag_model = """
REPNE does not modify flags.
"""

neon_assembly = """
// NEON lowering: REPNE stub (prefix)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

