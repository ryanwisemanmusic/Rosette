// RESTORE/FXRSTOR.inc
// Source contract: FXRSTOR — Restore x87 FPU, MMX Technology, and SSE State.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "RESTORE/FXRSTOR.inc"
x86_handler = "x86_fxrstor"
neon_lowering = "arm64_fxrstor"
lowering_kind = "arm64_documented_contract"

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
location. Operand must be 16-byte aligned. Loads all state including FSW,
FCW, FTW, FOP, FIP, FDP, ST0-ST7, MM0-MM7, XMM0-XMM15, and MXCSR.
"""

handler = "x86_fxrstor"
jit_lowering = "arm64_fxrstor"
fallback = "zig_fxrstor"

neon_register_model = """
FXRSTOR restores x87 FPU, MMX, XMM, and MXCSR state from memory. ARM64
NEON has no direct equivalent; software emulation of the restore format
is required.
"""

neon_flag_model = """
FXRSTOR does not modify flags.
"""

neon_assembly = """
// NEON lowering: software-emulated x87/MMX/SSE state restore from 512-byte buffer.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Must be 16-byte aligned; #GP if misaligned.",
  "#NM if CR0.TS or CR0.EM = 1.",
  "#UD if CPUID.01H:EDX.FXSR[bit 24] = 0 or LOCK prefix used.",
  "Bytes 464:511 are reserved and must not be loaded by software."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
