// OUTPUT/OUTSD.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "OUTPUT/OUTSD.inc"
x86_handler = "x86_outsd"
neon_lowering = "arm64_outsd"
lowering_kind = "arm64_documented_contract"
name = "OUTSD"
aliases = []
category = "io"
feature = "x86_gpr"
encodings = [
  { opcode = "6F", form = "OUTSD", op_en = "ZO", feature = "x86_gpr", vector_length = 0, encoding = "legacy" }
]
operand_encoding = { ZO = [] }
flags_written = []
floating_point_exceptions = []
other_exceptions = ["#GP if CPL > IOPL and port permission denied", "#UD if LOCK prefix used"]
semantic_general = "Output dword from DS:(E)SI/RSI to I/O port in DX, auto-increment/decrement address by 4."
handler = "x86_outsd"
jit_lowering = "arm64_outsd"
fallback = "zig_outsd"
neon_register_model = "OUTSD is an x86 I/O string instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: OUTSD stub"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
