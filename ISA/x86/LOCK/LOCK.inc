// LOCK/LOCK.inc
// Source contract: LOCK — prefix.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "LOCK/LOCK.inc"
x86_handler = "x86_lock"
neon_lowering = "arm64_lock"
lowering_kind = "arm64_documented_contract"

name = "LOCK"
aliases = []
category = "prefix"
feature = "general"
element_type = "none"
element_size = 0

encodings = [
  { opcode = "F0", form = "LOCK ", op_en = "ZO", feature = "general", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Assert LOCK# signal for duration of accompanying instruction.
"""

handler = "x86_lock"
jit_lowering = "arm64_lock"
fallback = "zig_lock"

neon_register_model = """
LOCK is a prefix instruction.
"""

neon_flag_model = """
LOCK does not modify flags.
"""

neon_assembly = """
// NEON lowering: LOCK stub (prefix)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
