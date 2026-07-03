// OUTPUT/OUTSB.inc
// ARM64/NEON mirror generated from ISA/x86/OUTPUT/OUTSB.inc.
semantic = """
OUTSB: output byte from memory to I/O port, auto-increment address by 1.
Category: io.
"""
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "OUTPUT/OUTSB.inc"
x86_handler = "x86_outsb"
neon_lowering = "arm64_outsb"
lowering_kind = "arm64_documented_contract"
name = "OUTSB"
aliases = []
category = "io"
feature = "x86_gpr"
encodings = [
  { opcode = "6E", form = "OUTSB", op_en = "ZO", feature = "x86_gpr", vector_length = 0, encoding = "legacy" }
]
operand_encoding = { ZO = [] }
flags_written = []
floating_point_exceptions = []
other_exceptions = ["#GP if CPL > IOPL and port permission denied", "#UD if LOCK prefix used"]
semantic_general = "Output byte from DS:(E)SI/RSI to I/O port in DX, auto-increment/decrement address by 1."
handler = "x86_outsb"
jit_lowering = "arm64_outsb"
fallback = "zig_outsb"
neon_register_model = "OUTSB is an x86 I/O string instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: OUTSB stub"
neon_notes = ["Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
