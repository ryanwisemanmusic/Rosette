// NEON/RESTORE/FXRSTOR.inc
// ARM64/NEON translation mirror generated from ISA/x86/RESTORE/FXRSTOR.inc.
// Source contract: FXRSTOR — Restore x87 FPU, MMX Technology, and SSE State.

semantic = """
Restore x87 FPU, MMX, XMM, and MXCSR register state from 512-byte memory location.
"""

source_isa = "arm64_neon"
target_isa = "x86"

name = "FXRSTOR"
aliases = ["FXRSTOR64"]
category = "x87_fpu_state"
feature = "FXSR"
element_type = "f32_f64_f80"

encodings = [
  { opcode = "NP 0F AE /1", form = "FXRSTOR m512byte", op_en = "M", feature = "FXSR", vector_length = 0, encoding = "legacy" },
  { opcode = "NP REX.W 0F AE /1", form = "FXRSTOR64 m512byte", op_en = "M", feature = "FXSR", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  M = ["ModRM:r/m (r)"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
Restore x87 FPU, MMX, XMM, and MXCSR register state from 512-byte memory
location. Must be 16-byte aligned.
"""

neon_register_model = """
FXRSTOR restores x87/MMX/XMM/MXCSR state. ARM64 no direct equivalent.
"""

neon_flag_model = """
FXRSTOR does not modify flags.
"""

neon_assembly = """
// NEON lowering: software-emulated x87/MMX/SSE state restore.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."
]
