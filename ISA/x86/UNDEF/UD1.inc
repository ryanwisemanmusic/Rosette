// UNDEF/UD1.inc
// UD1 — Undefined Instruction (RM form).

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "UNDEF/UD1.inc"
x86_handler = "x86_ud1"
neon_lowering = "arm64_ud1"
lowering_kind = "arm64_documented_contract"

name = "UD1"
aliases = []
category = "undefined"
feature = "general"

encodings = [
  { opcode = "0F B9 /r", form = "UD1 r32, r/m32", op_en = "RM", feature = "general", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  RM = ["ModRM:reg (r)", "ModRM:r/m (r)", "N/A", "N/A"]
}

flags_written = []
floating_point_exceptions = []
other_exceptions = ["#UD"]

semantic_general = """
Generates an invalid opcode exception (#UD). No other architectural effect.
UD1 with ModR/M byte is the two-byte undefined instruction (0F B9 /r).
"""

handler = "x86_ud1"
jit_lowering = "arm64_ud1"
fallback = "zig_ud1"

neon_register_model = "UD1 is an x86 exception-raising instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: UD1 stub — raise #UD"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
