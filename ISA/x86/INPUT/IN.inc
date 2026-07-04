// INPUT/IN.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INPUT/IN.inc"
x86_handler = "x86_in"
neon_lowering = "arm64_in"
lowering_kind = "arm64_documented_contract"
name = "IN"
aliases = []
category = "io"
feature = "x86_gpr"
encodings = [
  { opcode = "E4 ib", form = "IN AL, imm8", op_en = "I", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "E5 ib", form = "IN AX, imm8", op_en = "I", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "E5 ib", form = "IN EAX, imm8", op_en = "I", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "EC", form = "IN AL, DX", op_en = "ZO", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "ED", form = "IN AX, DX", op_en = "ZO", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "ED", form = "IN EAX, DX", op_en = "ZO", feature = "x86_gpr", vector_length = 0, encoding = "legacy" }
]
operand_encoding = { I = ["imm8"], ZO = [] }
flags_written = []
floating_point_exceptions = []
other_exceptions = ["#GP if CPL > IOPL and port permission denied", "#UD if LOCK prefix used"]
semantic_general = "Input byte/word/dword from I/O port specified by imm8 or DX into AL/AX/EAX."
handler = "x86_in"
jit_lowering = "arm64_in"
fallback = "zig_in"
neon_register_model = "IN is an x86 I/O port instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: IN stub"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
