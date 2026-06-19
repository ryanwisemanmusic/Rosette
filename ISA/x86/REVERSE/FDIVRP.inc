// REVERSE/FDIVRP.inc
// Source contract: FDIVRP — x87_fpu.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "REVERSE/FDIVRP.inc"
x86_handler = "x86_fdivrp"
neon_lowering = "arm64_fdivrp"
lowering_kind = "arm64_documented_contract"

name = "FDIVRP"
aliases = []
category = "x87_fpu"
feature = "x87_fpu"
element_type = "f80"
element_size = 80

encodings = [
  { opcode = "DE F0+i", form = "FDIVRP ST(i), ST(0)", op_en = "RM", feature = "x87_fpu", vector_length = 0, encoding = "legacy" }
  { opcode = "DE F1", form = "FDIVRP", op_en = "ZO", feature = "x87_fpu", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

flags_affected = ['C1', 'C0', 'C2', 'C3']

simd_fp_exceptions = []

semantic_general = """
Reverse Divide and Pop.
"""

handler = "x86_fdivrp"
jit_lowering = "arm64_fdivrp"
fallback = "zig_fdivrp"

neon_register_model = """
FDIVRP is a x87_fpu instruction.
"""

neon_flag_model = """
FDIVRP does not modify flags.
"""

neon_assembly = """
// NEON lowering: FDIVRP stub (x87_fpu)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

