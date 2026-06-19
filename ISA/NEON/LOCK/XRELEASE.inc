// LOCK/XRELEASE.inc
// ARM64/NEON mirror generated from ISA/x86/LOCK/XRELEASE.inc.
// Source contract: XRELEASE — prefix.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "LOCK/XRELEASE.inc"
x86_handler = "x86_xrelease"
neon_lowering = "arm64_xrelease"
lowering_kind = "arm64_documented_contract"

name = "XRELEASE"
aliases = []
category = "prefix"
feature = "hle"
element_type = "none"
element_size = 0

encodings = [
  { opcode = "F3", form = "XRELEASE ", op_en = "ZO", feature = "hle", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Hardware lock elision — end lock elision on memory operand.
"""

handler = "x86_xrelease"
jit_lowering = "arm64_xrelease"
fallback = "zig_xrelease"

neon_register_model = """
XRELEASE is a prefix instruction.
"""

neon_flag_model = """
XRELEASE does not modify flags.
"""

neon_assembly = """
// NEON lowering: XRELEASE stub (prefix)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
