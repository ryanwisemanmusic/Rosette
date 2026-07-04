// INPUT/INS.inc
// ARM64/NEON mirror generated from ISA/x86/INPUT/INS.inc.
semantic = """
INS: input byte/word/dword from I/O port to memory, auto-increment address.
Category: io.
"""
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INPUT/INS.inc"
x86_handler = "x86_ins"
neon_lowering = "arm64_ins"
lowering_kind = "arm64_documented_contract"
name = "INS"
aliases = []
category = "io"
feature = "x86_gpr"
encodings = [
  { opcode = "6C", form = "INS m8, DX", op_en = "ZO", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "6D", form = "INS m16, DX", op_en = "ZO", feature = "x86_gpr", vector_length = 0, encoding = "legacy" },
  { opcode = "6D", form = "INS m32, DX", op_en = "ZO", feature = "x86_gpr", vector_length = 0, encoding = "legacy" }
]
operand_encoding = { ZO = [] }
flags_written = []
floating_point_exceptions = []
other_exceptions = ["#GP if CPL > IOPL and port permission denied", "#UD if LOCK prefix used"]
semantic_general = "Input byte/word/dword from I/O port in DX to memory at ES:(E)DI/RDI, auto-increment/decrement address."
handler = "x86_ins"
jit_lowering = "arm64_ins"
fallback = "zig_ins"
neon_register_model = "INS is an x86 I/O string instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: INS stub"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
