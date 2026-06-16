// SET/STD.inc
// Source contract: STD — flag_control.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SET/STD.inc"
x86_handler = "x86_std"
neon_lowering = "arm64_std"
lowering_kind = "arm64_documented_contract"

name = "STD"
aliases = []
category = "flag_control"
feature = "x86_gpr"
element_type = "integer"
element_size = 0

encodings = [
  { opcode = "FD", form = "STD", op_en = "ZO", feature = "x86_gpr", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

flags_written = ["DF"]
simd_fp_exceptions = []

semantic_general = """
Sets the DF (direction) flag in EFLAGS, causing string operations to decrement.
"""

handler = "x86_std"
jit_lowering = "arm64_std"
fallback = "zig_std"

neon_register_model = """
x86 GPR mapped to ARM64 xN. STD is a flag_control instruction.
"""

neon_flag_model = """
No x86 flags are modified by STD.
"""

neon_assembly = """
// ARM64: direction flag mapped to software convention
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, and notes above are intentionally preserved as the source contract."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
