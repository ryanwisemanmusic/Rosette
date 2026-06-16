// SET/XSETBV.inc
// ARM64/NEON mirror generated from ISA/x86/SET/XSETBV.inc.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SET/XSETBV.inc"
x86_handler = "x86_xsetbv"
neon_lowering = "arm64_xsetbv"
lowering_kind = "arm64_documented_contract"

name = "XSETBV"
aliases = []
category = "control_register"
feature = "x86_gpr"
element_type = "integer"
element_size = 0

encodings = [
  { opcode = "NP 0F 01 D1", form = "XSETBV", op_en = "ZO", feature = "x86_gpr", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

flags_written = []
simd_fp_exceptions = [],

semantic_general = """
Writes ECX:EDX:EAX to a selected XCR (extended control register).
"""

handler = "x86_xsetbv"
jit_lowering = "arm64_xsetbv"
fallback = "zig_xsetbv"

neon_register_model = """
XSETBV is a control_register instruction. No ARM64-specific registers modified.
"""

neon_flag_model = """
No x86 flags modified by XSETBV.
"""

neon_assembly = """
// NEON lowering: XSETBV stub (x86-specific CR access)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
