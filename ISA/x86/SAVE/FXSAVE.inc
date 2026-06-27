// SAVE/FXSAVE.inc
// Source contract: FXSAVE — Save x87 FPU, MMX Technology, and SSE State.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SAVE/FXSAVE.inc"
x86_handler = "x86_fxsave"
neon_lowering = "arm64_fxsave"
lowering_kind = "arm64_documented_contract"

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
Retains register contents after save. Operand must be 16-byte aligned.
"""

handler = "x86_fxsave"
jit_lowering = "arm64_fxsave"
fallback = "zig_fxsave"

neon_register_model = """
FXSAVE saves x87 FPU, MMX, XMM, and MXCSR state. ARM64 NEON has no direct
equivalent; software emulation of the save format is required.
"""

neon_flag_model = """
FXSAVE does not modify flags.
"""

neon_assembly = """
// NEON lowering: software-emulated x87/MMX/SSE state save to 512-byte buffer.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Must be 16-byte aligned; #GP if misaligned.",
  "#NM if CR0.TS or CR0.EM = 1.",
  "#UD if CPUID.01H:EDX.FXSR[bit 24] = 0 or LOCK prefix used.",
  "Bytes 464:511 are available for software use (not written by processor)."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
