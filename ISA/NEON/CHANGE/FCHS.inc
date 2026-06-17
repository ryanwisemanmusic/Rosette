// CHANGE/FCHS.inc
// ARM64/NEON mirror generated from ISA/x86/CHANGE/FCHS.inc.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CHANGE/FCHS.inc"
x86_handler = "x86_fchs"
neon_lowering = "arm64_fchs"
lowering_kind = "arm64_documented_contract"

name = "FCHS"
aliases = []
category = "x87_fpu"
feature = "x87_fpu"
element_type = "f32_f64_f80"
element_size = 80

encodings = [
  { opcode = "D9 E0", form = "FCHS", op_en = "ZO", feature = "x87_fpu", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

flags_written = ["C1"]
simd_fp_exceptions = []

semantic_general = """
Complement the sign bit of ST(0).
"""

handler = "x86_fchs"
jit_lowering = "arm64_fchs"
fallback = "zig_fchs"

neon_register_model = """
FCHS is a x87_fpu instruction.
"""

neon_flag_model = """
FCHS writes C1.
"""

neon_assembly = """
// NEON lowering: ARM64 FNEG scalar instruction
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
