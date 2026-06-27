// NEON/SAVE/FSAVE.inc
// ARM64/NEON translation mirror generated from ISA/x86/SAVE/FSAVE.inc.
// Source contract: FSAVE/FNSAVE — Store x87 FPU State.

semantic = """
Store x87 FPU state to memory, then re-initialize the FPU.
"""

source_isa = "arm64_neon"
target_isa = "x86"

name = "FSAVE"
aliases = ["FNSAVE"]
category = "x87_fpu_state"
feature = "x87_fpu"
element_type = "f32_f64_f80"

encodings = [
  { opcode = "9B DD /6", form = "FSAVE m94/108byte", op_en = "M", feature = "x87_fpu", vector_length = 0, encoding = "legacy" },
  { opcode = "DD /6", form = "FNSAVE m94/108byte", op_en = "M", feature = "x87_fpu", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  M = ["ModRM:r/m (w)"]
}

flags_written = ["C0", "C1", "C2", "C3"]
simd_fp_exceptions = []

semantic_general = """
Store x87 FPU state to memory, then re-initialize the FPU.
FSAVE checks for pending unmasked exceptions; FNSAVE does not.
"""

neon_register_model = """
FSAVE/FNSAVE saves x87 FPU state to memory. ARM64 NEON has no direct
x87 FPU state; software emulation required.
"""

neon_flag_model = """
C0, C1, C2, C3 saved and then cleared.
"""

neon_assembly = """
// NEON lowering: software-emulated x87 FPU state save.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."
]
