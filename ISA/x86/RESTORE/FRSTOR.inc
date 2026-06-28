// RESTORE/FRSTOR.inc
// Source contract: FRSTOR — Restore x87 FPU State.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "RESTORE/FRSTOR.inc"
x86_handler = "x86_frstore"
neon_lowering = "arm64_frstore"
lowering_kind = "arm64_documented_contract"

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
Restore x87 FPU state (control word, status word, tag word, data pointer,
instruction pointer, last opcode, and register stack ST0-ST7) from memory.
All x87 FPU state is loaded from the 94-byte or 108-byte save image.
"""

handler = "x86_frstore"
jit_lowering = "arm64_frstore"
fallback = "zig_frstore"

neon_register_model = """
FRSTOR loads x87 FPU state from memory. ARM64 NEON has no direct x87 FPU
state; software emulation of the restore format is required.
"""

neon_flag_model = """
C0, C1, C2, C3 are loaded from the saved image.
"""

neon_assembly = """
// NEON lowering: software-emulated x87 FPU state restore from memory.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "FRSTOR restores state saved by FSAVE/FNSAVE; data must be in correct x87 save format.",
  "#NM if CR0.EM or CR0.TS = 1.",
  "#GP if source in non-readable segment or misaligned.",
  "#UD if LOCK prefix is used."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
