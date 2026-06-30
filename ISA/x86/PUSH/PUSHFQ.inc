// PUSH/PUSHFQ.inc
// PUSHFQ — Push RFLAGS Register Onto the Stack (64-bit operand size).

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "PUSH/PUSHFQ.inc"
x86_handler = "x86_pushfq"
neon_lowering = "arm64_pushfq"
lowering_kind = "arm64_documented_contract"

name = "PUSHFQ"
aliases = []
category = "stack_push"
feature = "general"

encodings = [
  { opcode = "9C", form = "PUSHFQ", op_en = "ZO", feature = "general", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = ["N/A", "N/A", "N/A", "N/A"]
}

flags_written = []
floating_point_exceptions = []
other_exceptions = ["#SS, #PF, #AC, #UD (if LOCK prefix used)"]

semantic_general = """
Decrement RSP by 8 and push RFLAGS onto stack. VM and RF flags cleared in stored image.
"""

handler = "x86_pushfq"
jit_lowering = "arm64_pushfq"
fallback = "zig_pushfq"

neon_register_model = "PUSHFQ is an x86 stack operation. Handled via system dispatch."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: PUSHFQ stub"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
