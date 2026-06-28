// NEON/RESTORE/FRSTOR.inc
// ARM64/NEON translation mirror generated from ISA/x86/RESTORE/FRSTOR.inc.
// Source contract: FRSTOR — Restore x87 FPU State.

semantic = """
Restore x87 FPU state from memory.
"""

source_isa = "arm64_neon"
target_isa = "x86"

name = "FRSTOR"
aliases = []
category = "x87_fpu_state"
feature = "x87_fpu"
element_type = "f32_f64_f80"

encodings = [
  { opcode = "DD /4", form = "FRSTOR m94/108byte", op_en = "M", feature = "x87_fpu", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  M = ["ModRM:r/m (r)"]
}

flags_written = ["C0", "C1", "C2", "C3"]
simd_fp_exceptions = []

semantic_general = """
Restore x87 FPU state from memory. All x87 FPU state is loaded from the
94-byte or 108-byte save image.
"""

neon_register_model = """
FRSTOR loads x87 FPU state from memory. ARM64 NEON no direct x87; software
emulation required.
"""

neon_flag_model = """
C0, C1, C2, C3 loaded from saved image.
"""

neon_assembly = """
// NEON lowering: software-emulated x87 FPU state restore.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."
]
