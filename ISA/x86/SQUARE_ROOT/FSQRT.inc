// SQUARE_ROOT/FSQRT.inc
// Source contract: FSQRT — x87_fpu.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SQUARE_ROOT/FSQRT.inc"
x86_handler = "x86_fsqrt"
neon_lowering = "arm64_fsqrt"
lowering_kind = "arm64_documented_contract"

name = "FSQRT"
aliases = []
category = "x87_fpu"
feature = "x87_fpu"
element_type = "f80"
element_size = 80

encodings = [
  { opcode = "D9 FA", form = "FSQRT", op_en = "ZO", feature = "x87_fpu", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

flags_affected = ['C1', 'C0', 'C2', 'C3']

simd_fp_exceptions = []

semantic_general = """
Square Root.
"""

handler = "x86_fsqrt"
jit_lowering = "arm64_fsqrt"
fallback = "zig_fsqrt"

neon_register_model = """
FSQRT is a x87_fpu instruction.
"""

neon_flag_model = """
FSQRT does not modify flags.
"""

neon_assembly = """
// NEON lowering: FSQRT stub (x87_fpu)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

