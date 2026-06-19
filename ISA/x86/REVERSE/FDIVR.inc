// REVERSE/FDIVR.inc
// Source contract: FDIVR — x87_fpu.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "REVERSE/FDIVR.inc"
x86_handler = "x86_fdivr"
neon_lowering = "arm64_fdivr"
lowering_kind = "arm64_documented_contract"

name = "FDIVR"
aliases = []
category = "x87_fpu"
feature = "x87_fpu"
element_type = "f80"
element_size = 80

encodings = [
  { opcode = "D8 /7", form = "FDIVR m32fp", op_en = "M", feature = "x87_fpu", vector_length = 0, encoding = "legacy" }
  { opcode = "DC /7", form = "FDIVR m64fp", op_en = "M", feature = "x87_fpu", vector_length = 0, encoding = "legacy" }
  { opcode = "D8 F8+i", form = "FDIVR ST(0), ST(i)", op_en = "MR", feature = "x87_fpu", vector_length = 0, encoding = "legacy" }
  { opcode = "DC F0+i", form = "FDIVR ST(i), ST(0)", op_en = "RM", feature = "x87_fpu", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

flags_affected = ['C1', 'C0', 'C2', 'C3']

simd_fp_exceptions = []

semantic_general = """
Reverse Divide.
"""

handler = "x86_fdivr"
jit_lowering = "arm64_fdivr"
fallback = "zig_fdivr"

neon_register_model = """
FDIVR is a x87_fpu instruction.
"""

neon_flag_model = """
FDIVR does not modify flags.
"""

neon_assembly = """
// NEON lowering: FDIVR stub (x87_fpu)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

