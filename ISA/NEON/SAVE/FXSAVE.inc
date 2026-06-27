// NEON/SAVE/FXSAVE.inc
// ARM64/NEON translation mirror generated from ISA/x86/SAVE/FXSAVE.inc.
// Source contract: FXSAVE — Save x87 FPU, MMX Technology, and SSE State.

semantic = """
Save x87 FPU, MMX, XMM, and MXCSR register state to 512-byte memory location.
"""

source_isa = "arm64_neon"
target_isa = "x86"

name = "FXSAVE"
aliases = ["FXSAVE64"]
category = "x87_fpu_state"
feature = "FXSR"
element_type = "f32_f64_f80"

encodings = [
  { opcode = "NP 0F AE /0", form = "FXSAVE m512byte", op_en = "M", feature = "FXSR", vector_length = 0, encoding = "legacy" },
  { opcode = "NP REX.W 0F AE /0", form = "FXSAVE64 m512byte", op_en = "M", feature = "FXSR", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  M = ["ModRM:r/m (w)"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
Save x87 FPU, MMX, XMM, and MXCSR register state to 512-byte memory location.
Retains register contents after save. Must be 16-byte aligned.
"""

neon_register_model = """
FXSAVE saves x87 FPU, MMX, XMM, MXCSR state. ARM64 no direct equivalent.
"""

neon_flag_model = """
FXSAVE does not modify flags.
"""

neon_assembly = """
// NEON lowering: software-emulated x87/MMX/SSE state save.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."
]
