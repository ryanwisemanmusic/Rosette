// WAIT/MWAIT.inc
// Source contract: MWAIT — power_mgmt.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "WAIT/MWAIT.inc"
x86_handler = "x86_mwait"
neon_lowering = "arm64_mwait"
lowering_kind = "arm64_documented_contract"

name = "MWAIT"
aliases = []
category = "power_mgmt"
feature = "monitor"
element_type = "none"
element_size = 0

encodings = [
  { opcode = "0F 01 C9", form = "MWAIT", op_en = "ZO", feature = "monitor", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Monitor Wait.
"""

handler = "x86_mwait"
jit_lowering = "arm64_mwait"
fallback = "zig_mwait"

neon_register_model = """
MWAIT is a power_mgmt instruction.
"""

neon_flag_model = """
MWAIT does not modify flags.
"""

neon_assembly = """
// NEON lowering: MWAIT stub (power_mgmt)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

