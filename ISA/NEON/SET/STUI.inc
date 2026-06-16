// SET/STUI.inc
// ARM64/NEON mirror generated from ISA/x86/SET/STUI.inc.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SET/STUI.inc"
x86_handler = "x86_stui"
neon_lowering = "arm64_stui"
lowering_kind = "arm64_documented_contract"

name = "STUI"
aliases = []
category = "flag_control"
feature = "UINTR"
element_type = "integer"
element_size = 0

encodings = [
  { opcode = "F3 0F 01 EB", form = "STUI", op_en = "ZO", feature = "UINTR", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

flags_written = []
simd_fp_exceptions = [],

semantic_general = """
Sets the UIF (user interrupt) flag, enabling user-level interrupts.
"""

handler = "x86_stui"
jit_lowering = "arm64_stui"
fallback = "zig_stui"

neon_register_model = """
STUI is a flag_control instruction. No ARM64-specific registers modified.
"""

neon_flag_model = """
No x86 flags modified by STUI.
"""

neon_assembly = """
// NEON lowering: user interrupt enable stub
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
