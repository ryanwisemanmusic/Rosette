// OUTPUT/OUTS.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "OUTPUT/OUTS.inc"
x86_handler = "x86_outs"
neon_lowering = "arm64_outs"
lowering_kind = "arm64_documented_contract"
name = "OUTS"
aliases = []
category = "io"
feature = "x86_gpr"
encodings = [
  { opcode = "6E", form = "OUTS DX, m8", op_en = "ZO", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "6F", form = "OUTS DX, m16", op_en = "ZO", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "6F", form = "OUTS DX, m32", op_en = "ZO", feature = "x86_gpr", vector_length = 0, encoding = "legacy" }
]
operand_encoding = { ZO = [] }
flags_written = []
floating_point_exceptions = []
other_exceptions = ["#GP if CPL > IOPL and port permission denied", "#UD if LOCK prefix used"]
semantic_general = "Output byte/word/dword from memory at DS:(E)SI/RSI to I/O port in DX, auto-increment/decrement address."
handler = "x86_outs"
jit_lowering = "arm64_outs"
fallback = "zig_outs"
neon_register_model = "OUTS is an x86 I/O string instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: OUTS stub"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
