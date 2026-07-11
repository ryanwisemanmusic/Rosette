// MUL/FIMUL.inc
// ARM64/NEON translation mirror generated from ISA/x86/MUL/FIMUL.inc.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "MUL/FIMUL.inc"
x86_handler = "x86_fimul"
neon_lowering = "arm64_neon_fimul"
lowering_kind = "neon_x87"

name = "FIMUL"
category = "gpr_x87_alu"
feature = "x87 FPU"
element_type = "f80"

encodings = [
  { opcode = "DA /1", form = "FIMUL m32int", op_en = "M", feature = "x87 FPU" },
  { opcode = "DE /1", form = "FIMUL m16int", op_en = "M", feature = "x87 FPU" },
]

lanes = { xmm = 0, ymm = 0 }
flags_written = ["C1"]
simd_fp_exceptions = []
other_exceptions = [
  "#IS if stack underflow",
  "#IA if integer conversion yields SNaN or unsupported format",
  "#D if denormal source",
  "#U if result too small",
  "#O if result too large",
  "#P if inexact",
  "#NM if CR0.EM or CR0.TS = 1",
  "#UD if LOCK prefix"
]

semantic_general = """
DEST := DEST * ConvertToDoubleExtendedPrecisionFP(SRC);
"""

neon_register_model = """
x87 FPU register stack is mapped to the ARM64 FP/SIMD register file; integer-to-FP conversion precedes the multiply.
"""

neon_flag_model = """
x87 condition code C1 (stack underflow/overflow) is derived from the ARM64 FP/SIMD exception state via Rosette x87 exception handlers.
"""

neon_assembly = """
scvtf dTMP, wSRC
fmul dD, dN, dTMP
bl rosette_apply_x87_fp_exceptions
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

handler = "x86_fimul"
jit_lowering = "arm64_neon_fimul"
fallback = "zig_x87_fallback"
