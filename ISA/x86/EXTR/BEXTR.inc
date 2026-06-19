// EXTR/BEXTR.inc
// Source contract: BEXTR — bit_manipulation.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "EXTR/BEXTR.inc"
x86_handler = "x86_bextr"
neon_lowering = "arm64_bextr"
lowering_kind = "arm64_documented_contract"

name = "BEXTR"
aliases = []
category = "bit_manipulation"
feature = "bmi1"
element_type = "none"
element_size = 0

encodings = [
  { opcode = "VEX.LZ.0F38.W0 F7 /r", form = "BEXTR r32a, r/m32, r32b", op_en = "RMV", feature = "bmi1", vector_length = 0, encoding = "vex" }
  { opcode = "VEX.LZ.0F38.W1 F7 /r", form = "BEXTR r64a, r/m64, r64b", op_en = "RMV", feature = "bmi1", vector_length = 0, encoding = "vex" }
]

operand_encoding = {
  RMV = []
}

flags_affected = ['ZF']

simd_fp_exceptions = []

semantic_general = """
Bit field extract (contiguous) from r/m using register control.
"""

handler = "x86_bextr"
jit_lowering = "arm64_bextr"
fallback = "zig_bextr"

neon_register_model = """
BEXTR is a BMI bit manipulation instruction.
"""

neon_flag_model = """
BEXTR affects: ZF.
"""

neon_assembly = """
// NEON lowering: BEXTR stub (bit_manipulation)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
