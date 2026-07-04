// INPUT/INSD.inc
// ARM64/NEON mirror generated from ISA/x86/INPUT/INSD.inc.
semantic = """
INSD: input dword from I/O port to memory, auto-increment address by 4.
Category: io.
"""
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INPUT/INSD.inc"
x86_handler = "x86_insd"
neon_lowering = "arm64_insd"
lowering_kind = "arm64_documented_contract"
name = "INSD"
aliases = []
category = "io"
feature = "x86_gpr"
encodings = [
  { opcode = "6D", form = "INSD", op_en = "ZO", feature = "x86_gpr", vector_length = 0, encoding = "legacy" }
]
operand_encoding = { ZO = [] }
flags_written = []
floating_point_exceptions = []
other_exceptions = ["#GP if CPL > IOPL and port permission denied", "#UD if LOCK prefix used"]
semantic_general = "Input dword from I/O port in DX to memory at ES:(E)DI/RDI, auto-increment/decrement address by 4."
handler = "x86_insd"
jit_lowering = "arm64_insd"
fallback = "zig_insd"
neon_register_model = "INSD is an x86 I/O string instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: INSD stub"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
