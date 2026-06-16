// SET/STC.inc
// Source contract: STC — flag_control.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SET/STC.inc"
x86_handler = "x86_stc"
neon_lowering = "arm64_stc"
lowering_kind = "arm64_documented_contract"

name = "STC"
aliases = []
category = "flag_control"
feature = "x86_gpr"
element_type = "integer"
element_size = 0

encodings = [
  { opcode = "F9", form = "STC", op_en = "ZO", feature = "x86_gpr", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

flags_written = ["CF"]
simd_fp_exceptions = []

semantic_general = """
Sets the CF (carry) flag in EFLAGS.
"""

handler = "x86_stc"
jit_lowering = "arm64_stc"
fallback = "zig_stc"

neon_register_model = """
x86 GPR mapped to ARM64 xN. STC is a flag_control instruction.
"""

neon_flag_model = """
No x86 flags are modified by STC.
"""

neon_assembly = """
// ARM64: MSR nzcv, xTMP
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, and notes above are intentionally preserved as the source contract."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
