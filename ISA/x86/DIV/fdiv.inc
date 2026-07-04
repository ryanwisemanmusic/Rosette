// DIV/fdiv.inc
// ARM64/NEON translation mirror generated from ISA/x86/DIV/fdiv.inc.
// Source contract: FDIV — Divide (x87 FPU).

semantic = """
DEST := DEST / SRC
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "DIV/fdiv.inc"
x86_handler = "x86_fdiv"
neon_lowering = "arm64_fdiv"
lowering_kind = "arm64_scalar"

name = "FDIV"
aliases = []
category = "floating_point_div"
feature = "x87_fpu"
element_type = "f80"

encodings = [
  { opcode = "D8 /6", form = "FDIV m32fp", op_en = "M", feature = "x87_FPU", vector_length = 0, encoding = "legacy" },
  { opcode = "DC /6", form = "FDIV m64fp", op_en = "M", feature = "x87_FPU", vector_length = 0, encoding = "legacy" },
  { opcode = "D8 F0+i", form = "FDIV ST(0), ST(i)", op_en = "RR", feature = "x87_FPU", vector_length = 0, encoding = "legacy" },
  { opcode = "DC F8+i", form = "FDIV ST(i), ST(0)", op_en = "RR", feature = "x87_FPU", vector_length = 0, encoding = "legacy" },
]

operand_encoding = {
  M = ["ModRM:r/m (r)"],
  RR = ["ST(i) (r,w)", "ST(0) (r)"]
}

lanes = { xmm = 0, ymm = 0 }
flags_written = ["C1"]
simd_fp_exceptions = []
other_exceptions = [
  "#IS if stack underflow",
  "#IA if SNaN or zero/zero or inf/inf",
  "#D if denormal source",
  "#U if result too small",
  "#O if result too large",
  "#Z if divide-by-zero",
  "#P if inexact",
  "#NM if CR0.EM or CR0.TS = 1",
  "#UD if LOCK prefix"
]

semantic_general = """
DEST := DEST / SRC;
"""

handler = "x86_fdiv"
jit_lowering = "arm64_fdiv"
fallback = "zig_fdiv"

neon_register_model = """
x87 FPU stack mapped to ARM64 vN registers. FDIV is a scalar division on x87 top-of-stack.
"""

neon_flag_model = """
ARM64 FDIV does not update flags. x87 C1 flag needs separate tracking if required.
"""

neon_assembly = """
// NEON lowering: fdiv dDEST, dSRC
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
