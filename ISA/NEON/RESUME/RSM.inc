// RESUME/RSM.inc
// ARM64/NEON mirror generated from ISA/x86/RESUME/RSM.inc.
// Source contract: RSM — system.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "RESUME/RSM.inc"
x86_handler = "x86_rsm"
neon_lowering = "arm64_rsm"
lowering_kind = "arm64_documented_contract"

name = "RSM"
aliases = []
category = "system"
feature = "smx"
element_type = "none"
element_size = 0

encodings = [
  { opcode = "0F AA", form = "RSM ", op_en = "ZO", feature = "smx", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

flags_affected = ['ALL']

simd_fp_exceptions = []

semantic_general = """
Resume from system management mode (SMM).
"""

handler = "x86_rsm"
jit_lowering = "arm64_rsm"
fallback = "zig_rsm"

neon_register_model = """
RSM is a system-level instruction.
"""

neon_flag_model = """
RSM affects: ALL.
"""

neon_assembly = """
// NEON lowering: RSM stub (system)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
