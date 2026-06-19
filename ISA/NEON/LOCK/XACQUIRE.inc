// LOCK/XACQUIRE.inc
// ARM64/NEON mirror generated from ISA/x86/LOCK/XACQUIRE.inc.
// Source contract: XACQUIRE — prefix.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "LOCK/XACQUIRE.inc"
x86_handler = "x86_xacquire"
neon_lowering = "arm64_xacquire"
lowering_kind = "arm64_documented_contract"

name = "XACQUIRE"
aliases = []
category = "prefix"
feature = "hle"
element_type = "none"
element_size = 0

encodings = [
  { opcode = "F2", form = "XACQUIRE ", op_en = "ZO", feature = "hle", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Hardware lock elision — start lock elision on memory operand.
"""

handler = "x86_xacquire"
jit_lowering = "arm64_xacquire"
fallback = "zig_xacquire"

neon_register_model = """
XACQUIRE is a prefix instruction.
"""

neon_flag_model = """
XACQUIRE does not modify flags.
"""

neon_assembly = """
// NEON lowering: XACQUIRE stub (prefix)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
