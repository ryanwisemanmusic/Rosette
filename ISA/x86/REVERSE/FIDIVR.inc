// REVERSE/FIDIVR.inc
// Source contract: FIDIVR — x87_fpu.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "REVERSE/FIDIVR.inc"
x86_handler = "x86_fidivr"
neon_lowering = "arm64_fidivr"
lowering_kind = "arm64_documented_contract"

name = "FIDIVR"
aliases = []
category = "x87_fpu"
feature = "x87_fpu"
element_type = "f80"
element_size = 80

encodings = [
  { opcode = "DA /7", form = "FIDIVR m32int", op_en = "M", feature = "x87_fpu", vector_length = 0, encoding = "legacy" }
  { opcode = "DE /7", form = "FIDIVR m16int", op_en = "M", feature = "x87_fpu", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

flags_affected = ['C1', 'C0', 'C2', 'C3']

simd_fp_exceptions = []

semantic_general = """
Reverse Divide with Integer.
"""

handler = "x86_fidivr"
jit_lowering = "arm64_fidivr"
fallback = "zig_fidivr"

neon_register_model = """
FIDIVR is a x87_fpu instruction.
"""

neon_flag_model = """
FIDIVR does not modify flags.
"""

neon_assembly = """
// NEON lowering: FIDIVR stub (x87_fpu)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

