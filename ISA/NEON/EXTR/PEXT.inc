// EXTR/PEXT.inc
// ARM64/NEON mirror generated from ISA/x86/EXTR/PEXT.inc.
// Source contract: PEXT — bit_manipulation.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "EXTR/PEXT.inc"
x86_handler = "x86_pext"
neon_lowering = "arm64_pext"
lowering_kind = "arm64_documented_contract"

name = "PEXT"
aliases = []
category = "bit_manipulation"
feature = "bmi2"
element_type = "none"
element_size = 0

encodings = [
  { opcode = "VEX.LZ.F3.0F38.W0 F5 /r", form = "PEXT r32a, r32b, r/m32", op_en = "RVM", feature = "bmi2", vector_length = 0, encoding = "vex" }
  { opcode = "VEX.LZ.F3.0F38.W1 F5 /r", form = "PEXT r64a, r64b, r/m64", op_en = "RVM", feature = "bmi2", vector_length = 0, encoding = "vex" }
]

operand_encoding = {
  RVM = []
}

simd_fp_exceptions = []

semantic_general = """
Parallel bits extract — copy selected bits to contiguous low positions.
"""

handler = "x86_pext"
jit_lowering = "arm64_pext"
fallback = "zig_pext"

neon_register_model = """
PEXT is a BMI bit manipulation instruction.
"""

neon_flag_model = """
PEXT does not modify flags.
"""

neon_assembly = """
// NEON lowering: PEXT stub (bit_manipulation)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
