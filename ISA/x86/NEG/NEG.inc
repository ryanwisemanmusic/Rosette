// NEG/NEG.inc
// Source contract: NEG — arithmetic.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "NEG/NEG.inc"
x86_handler = "x86_neg"
neon_lowering = "arm64_neg"
lowering_kind = "arm64_documented_contract"

name = "NEG"
aliases = []
category = "arithmetic"
feature = "general"
element_type = "none"
element_size = 0

encodings = [
  { opcode = "F6 /3", form = "NEG r/m8", op_en = "M", feature = "general", vector_length = 0, encoding = "legacy" }
  { opcode = "REX + F6 /3", form = "NEG r/m8", op_en = "M", feature = "general", vector_length = 0, encoding = "legacy" }
  { opcode = "F7 /3", form = "NEG r/m16", op_en = "M", feature = "general", vector_length = 0, encoding = "legacy" }
  { opcode = "F7 /3", form = "NEG r/m32", op_en = "M", feature = "general", vector_length = 0, encoding = "legacy" }
  { opcode = "REX.W + F7 /3", form = "NEG r/m64", op_en = "M", feature = "general", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  M = []
}

flags_affected = ['CF', 'OF', 'SF', 'ZF', 'AF', 'PF']

simd_fp_exceptions = []

semantic_general = """
Two's complement negation — subtract operand from 0.
"""

handler = "x86_neg"
jit_lowering = "arm64_neg"
fallback = "zig_neg"

neon_register_model = """
NEG is a arithmetic instruction.
"""

neon_flag_model = """
NEG affects: CF, OF, SF, ZF, AF, PF.
"""

neon_assembly = """
// NEON lowering: NEG stub (arithmetic)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
