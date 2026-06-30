// PUSH/PUSHFD.inc
// PUSHFD — Push EFLAGS Register Onto the Stack (32-bit operand size).

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "PUSH/PUSHFD.inc"
x86_handler = "x86_pushfd"
neon_lowering = "arm64_pushfd"
lowering_kind = "arm64_documented_contract"

name = "PUSHFD"
aliases = []
category = "stack_push"
feature = "general"

encodings = [
  { opcode = "9C", form = "PUSHFD", op_en = "ZO", feature = "general", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = ["N/A", "N/A", "N/A", "N/A"]
}

flags_written = []
floating_point_exceptions = []
other_exceptions = ["#SS, #PF, #AC, #UD (if LOCK prefix used)"]

semantic_general = """
Decrement stack pointer by 4 and push EFLAGS onto stack. VM and RF flags cleared in stored image.
"""

handler = "x86_pushfd"
jit_lowering = "arm64_pushfd"
fallback = "zig_pushfd"

neon_register_model = "PUSHFD is an x86 stack operation. Handled via system dispatch."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: PUSHFD stub"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
