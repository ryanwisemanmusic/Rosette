// REVERSE/FSUBRP.inc
// Source contract: FSUBRP — x87_fpu.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "REVERSE/FSUBRP.inc"
x86_handler = "x86_fsubrp"
neon_lowering = "arm64_fsubrp"
lowering_kind = "arm64_documented_contract"

name = "FSUBRP"
aliases = []
category = "x87_fpu"
feature = "x87_fpu"
element_type = "f80"
element_size = 80

encodings = [
  { opcode = "DE E0+i", form = "FSUBRP ST(i), ST(0)", op_en = "RM", feature = "x87_fpu", vector_length = 0, encoding = "legacy" }
  { opcode = "DE E1", form = "FSUBRP", op_en = "ZO", feature = "x87_fpu", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

flags_affected = ['C1', 'C0', 'C2', 'C3']

simd_fp_exceptions = []

semantic_general = """
Reverse Subtract and Pop.
"""

handler = "x86_fsubrp"
jit_lowering = "arm64_fsubrp"
fallback = "zig_fsubrp"

neon_register_model = """
FSUBRP is a x87_fpu instruction.
"""

neon_flag_model = """
FSUBRP does not modify flags.
"""

neon_assembly = """
// NEON lowering: FSUBRP stub (x87_fpu)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

