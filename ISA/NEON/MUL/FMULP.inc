// MUL/FMULP.inc
// ARM64/NEON translation mirror generated from ISA/x86/MUL/FMULP.inc.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "MUL/FMULP.inc"
x86_handler = "x86_fmulp"
neon_lowering = "arm64_neon_fmul_scalar_pop"
lowering_kind = "neon_x87"

name = "FMULP"
category = "gpr_x87_alu"
feature = "x87 FPU"
element_type = "f80"

encodings = [
  { opcode = "DE C8+i", form = "FMULP ST(i), ST(0)", op_en = "A", feature = "x87 FPU" },
  { opcode = "DE C9", form = "FMULP", op_en = "ZO", feature = "x87 FPU" },
]

lanes = { xmm = 0, ymm = 0 }
flags_written = ["C1"]
simd_fp_exceptions = []
other_exceptions = [
  "#IS if stack underflow",
  "#IA if SNaN or unsupported format",
  "#D if denormal source",
  "#U if result too small",
  "#O if result too large",
  "#P if inexact",
  "#NM if CR0.EM or CR0.TS = 1",
  "#UD if LOCK prefix"
]

semantic_general = """
DEST := DEST * ST(0);
PopRegisterStack;
"""

neon_register_model = """
x87 FPU register stack is mapped to the ARM64 FP/SIMD register file; the pop operation is emulated by rotating the stack pointer.
"""

neon_flag_model = """
x87 condition code C1 (stack underflow/overflow) is derived from the ARM64 FP/SIMD exception state via Rosette x87 exception handlers.
"""

neon_assembly = """
fmul dD, dN, dM
bl rosette_x87_stack_pop
bl rosette_apply_x87_fp_exceptions
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

handler = "x86_fmulp"
jit_lowering = "arm64_neon_fmul_scalar_pop"
fallback = "zig_x87_fallback"
