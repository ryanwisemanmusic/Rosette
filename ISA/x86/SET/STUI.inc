// SET/STUI.inc
// Source contract: STUI — flag_control.

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
simd_fp_exceptions = []

semantic_general = """
Sets the UIF (user interrupt) flag, enabling user-level interrupts.
"""

handler = "x86_stui"
jit_lowering = "arm64_stui"
fallback = "zig_stui"

neon_register_model = """
x86 GPR mapped to ARM64 xN. STUI is a flag_control instruction.
"""

neon_flag_model = """
No x86 flags are modified by STUI.
"""

neon_assembly = """
// NEON lowering: user interrupt enable stub
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, and notes above are intentionally preserved as the source contract."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
