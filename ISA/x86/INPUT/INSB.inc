// INPUT/INSB.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INPUT/INSB.inc"
x86_handler = "x86_insb"
neon_lowering = "arm64_insb"
lowering_kind = "arm64_documented_contract"
name = "INSB"
aliases = []
category = "io"
feature = "x86_gpr"
encodings = [
  { opcode = "6C", form = "INSB", op_en = "ZO", feature = "x86_gpr", vector_length = 0, encoding = "legacy" }
]
operand_encoding = { ZO = [] }
flags_written = []
floating_point_exceptions = []
other_exceptions = ["#GP if CPL > IOPL and port permission denied", "#UD if LOCK prefix used"]
semantic_general = "Input byte from I/O port in DX to memory at ES:(E)DI/RDI, auto-increment/decrement address by 1."
handler = "x86_insb"
jit_lowering = "arm64_insb"
fallback = "zig_insb"
neon_register_model = "INSB is an x86 I/O string instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: INSB stub"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
