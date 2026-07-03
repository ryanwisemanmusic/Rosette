// OUTPUT/OUT.inc
// ARM64/NEON mirror generated from ISA/x86/OUTPUT/OUT.inc.
semantic = """
OUT: output byte/word/dword from AL/AX/EAX to I/O port.
Category: io.
"""
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "OUTPUT/OUT.inc"
x86_handler = "x86_out"
neon_lowering = "arm64_out"
lowering_kind = "arm64_documented_contract"
name = "OUT"
aliases = []
category = "io"
feature = "x86_gpr"
encodings = [
  { opcode = "E6 ib", form = "OUT imm8, AL", op_en = "I", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "E7 ib", form = "OUT imm8, AX", op_en = "I", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "E7 ib", form = "OUT imm8, EAX", op_en = "I", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "EE", form = "OUT DX, AL", op_en = "ZO", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "EF", form = "OUT DX, AX", op_en = "ZO", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "EF", form = "OUT DX, EAX", op_en = "ZO", feature = "x86_gpr", vector_length = 0, encoding = "legacy" }
]
operand_encoding = { I = ["imm8"], ZO = [] }
flags_written = []
floating_point_exceptions = []
other_exceptions = ["#GP if CPL > IOPL and port permission denied", "#UD if LOCK prefix used"]
semantic_general = "Output byte/word/dword from AL/AX/EAX to I/O port specified by imm8 or DX."
handler = "x86_out"
jit_lowering = "arm64_out"
fallback = "zig_out"
neon_register_model = "OUT is an x86 I/O port instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: OUT stub"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
