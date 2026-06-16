// SET/STI.inc
// ARM64/NEON mirror generated from ISA/x86/SET/STI.inc.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SET/STI.inc"
x86_handler = "x86_sti"
neon_lowering = "arm64_sti"
lowering_kind = "arm64_documented_contract"

name = "STI"
aliases = []
category = "flag_control"
feature = "x86_gpr"
element_type = "integer"
element_size = 0

encodings = [
  { opcode = "FB", form = "STI", op_en = "ZO", feature = "x86_gpr", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

flags_written = ["IF"]
simd_fp_exceptions = [],

semantic_general = """
Sets the IF (interrupt) flag in EFLAGS, enabling maskable hardware interrupts.
"""

handler = "x86_sti"
jit_lowering = "arm64_sti"
fallback = "zig_sti"

neon_register_model = """
STI is a flag_control instruction. No ARM64-specific registers modified.
"""

neon_flag_model = """
No x86 flags modified by STI.
"""

neon_assembly = """
// ARM64: MSR DAIF or PSTATE
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
