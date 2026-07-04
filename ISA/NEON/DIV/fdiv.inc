// DIV/fdiv.inc
// ARM64/NEON mirror generated from ISA/x86/DIV/fdiv.inc.
// This file preserves the x86 source contract and supplies the ARM64 lowering contract.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "DIV/fdiv.inc"
x86_handler = "x86_fdiv"
neon_lowering = "arm64_fdiv"
lowering_kind = "arm64_documented_contract"

// DIV/fdiv.inc
// ARM64/NEON translation mirror generated from ISA/x86/DIV/fdiv.inc.
// Source contract: FDIV — Divide (x87 FPU).

semantic = """
DEST := DEST / SRC
"""

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
