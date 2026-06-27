// SAVE/FSAVE.inc
// Source contract: FSAVE/FNSAVE — Store x87 FPU State.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SAVE/FSAVE.inc"
x86_handler = "x86_fsave"
neon_lowering = "arm64_fsave"
lowering_kind = "arm64_documented_contract"

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
Store x87 FPU state (control word, status word, tag word, data pointer,
instruction pointer, last opcode, and register stack ST0-ST7) to memory,
then re-initialize the FPU. FSAVE checks for pending unmasked exceptions;
FNSAVE does not.
"""

handler = "x86_fsave"
jit_lowering = "arm64_fsave"
fallback = "zig_fsave"

neon_register_model = """
FSAVE/FNSAVE saves x87 FPU state to memory. ARM64 NEON has no direct
x87 FPU state; software emulation of the save format is required.
"""

neon_flag_model = """
C0, C1, C2, C3 are saved and then cleared.
"""

neon_assembly = """
// NEON lowering: software-emulated x87 FPU state save to memory.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "FSAVE implies FWAIT before FNSAVE; FNSAVE does not check pending exceptions.",
  "#NM if CR0.EM or CR0.TS = 1.",
  "#GP if destination in non-writable segment or misaligned.",
  "#UD if LOCK prefix is used."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
