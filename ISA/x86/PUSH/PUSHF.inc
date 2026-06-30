// PUSH/PUSHF.inc
// PUSHF — Push FLAGS Register Onto the Stack (16-bit operand size).

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "PUSH/PUSHF.inc"
x86_handler = "x86_pushf"
neon_lowering = "arm64_pushf"
lowering_kind = "arm64_documented_contract"

name = "PUSHF"
aliases = []
category = "stack_push"
feature = "general"

encodings = [
  { opcode = "9C", form = "PUSHF", op_en = "ZO", feature = "general", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = ["N/A", "N/A", "N/A", "N/A"]
}

flags_written = []
floating_point_exceptions = []
other_exceptions = ["#SS, #PF, #AC, #UD (if LOCK prefix used)"]

semantic_general = """
Decrement stack pointer by 2 and push lower 16 bits of EFLAGS (FLAGS) onto stack.
"""

handler = "x86_pushf"
jit_lowering = "arm64_pushf"
fallback = "zig_pushf"

neon_register_model = "PUSHF is an x86 stack operation. Handled via system dispatch."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: PUSHF stub"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
