// SCAN/SCASD.inc
// ARM64/NEON mirror generated from ISA/x86/SCAN/SCASD.inc.
// Source contract: SCASD — string_op.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SCAN/SCASD.inc"
x86_handler = "x86_scasd"
neon_lowering = "arm64_scasd"
lowering_kind = "arm64_documented_contract"

name = "SCASD"
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
Scan String Doubleword.
"""

handler = "x86_scasd"
jit_lowering = "arm64_scasd"
fallback = "zig_scasd"

neon_register_model = """
SCASD is a string_op instruction.
"""

neon_flag_model = """
SCASD does not modify flags.
"""

neon_assembly = """
// NEON lowering: SCASD stub (string_op)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

