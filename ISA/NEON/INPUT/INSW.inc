// INPUT/INSW.inc
// ARM64/NEON mirror generated from ISA/x86/INPUT/INSW.inc.
semantic = """
INSW: input word from I/O port to memory, auto-increment address by 2.
Category: io.
"""
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INPUT/INSW.inc"
x86_handler = "x86_insw"
neon_lowering = "arm64_insw"
lowering_kind = "arm64_documented_contract"
name = "INSW"
aliases = []
category = "io"
feature = "x86_gpr"
encodings = [
  { opcode = "6D", form = "INSW", op_en = "ZO", feature = "x86_gpr", vector_length = 0, encoding = "legacy" }
]
operand_encoding = { ZO = [] }
flags_written = []
floating_point_exceptions = []
other_exceptions = ["#GP if CPL > IOPL and port permission denied", "#UD if LOCK prefix used"]
semantic_general = "Input word from I/O port in DX to memory at ES:(E)DI/RDI, auto-increment/decrement address by 2."
handler = "x86_insw"
jit_lowering = "arm64_insw"
fallback = "zig_insw"
neon_register_model = "INSW is an x86 I/O string instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: INSW stub"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
