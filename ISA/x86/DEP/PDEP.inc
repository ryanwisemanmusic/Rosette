// DEP/PDEP.inc
// Source contract: PDEP — Parallel Bits Deposit.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "DEP/PDEP.inc"
x86_handler = "x86_pdep"
neon_lowering = "arm64_pdep"
lowering_kind = "arm64_documented_contract"

name = "PDEP"
aliases = []
category = "bmi2_bit_deposit"
feature = "bmi2"

encodings = [
  { opcode = "VEX.LZ.F2.0F38.W0 F5 /r", form = "PDEP r32a, r32b, r/m32", op_en = "RVM", feature = "bmi2", vector_length = 0, encoding = "vex" },
  { opcode = "VEX.LZ.F2.0F38.W1 F5 /r", form = "PDEP r64a, r64b, r/m64", op_en = "RVM", feature = "bmi2", vector_length = 0, encoding = "vex" }
]

operand_encoding = {
  RVM = ["ModRM:reg (w)", "VEX.vvvv (r)", "ModRM:r/m (r)"]
}

lanes = { gpr = 1 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "See Table 2-29, Type 13 Class Exception Conditions."
]

semantic_general = """
Scatters contiguous low-order bits from SRC1 to bit positions set in MASK, zeroing all other destination bits.
"""

handler = "x86_pdep"
jit_lowering = "arm64_pdep"
fallback = "zig_pdep"

neon_register_model = """
PDEP is a BMI2 GPR bit-deposit operation.
"""

neon_flag_model = """
PDEP does not modify flags.
"""

neon_assembly = """
// NEON lowering: PDEP stub (BMI2 parallel bits deposit)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
