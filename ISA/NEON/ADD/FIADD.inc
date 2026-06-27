// ADD/FIADD.inc
// ARM64/NEON mirror generated from ISA/x86/ADD/FIADD.inc.
// This file preserves the x86 source contract and supplies the ARM64 lowering contract.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ADD/FIADD.inc"
x86_handler = "x86_fiadd"
neon_lowering = "arm64_fiadd"
lowering_kind = "arm64_documented_contract"

// ADD/FIADD.inc
// ARM64/NEON translation mirror generated from ISA/x86/ADD/FIADD.inc.
// Source contract: FIADD — Add Integer to FPU.

semantic = """
DEST := DEST + ConvertToDoubleExtendedPrecisionFP(SRC)
"""

name = "FIADD"
category = "floating_point_add"
feature = "x87_fpu"
element_type = "f80"

encodings = [
  { opcode = "DA /0", form = "FIADD m32int", op_en = "M", feature = "x87_FPU", vector_length = 0, encoding = "legacy" },
  { opcode = "DE /0", form = "FIADD m16int", op_en = "M", feature = "x87_FPU", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  M = ["ModRM:r/m (r)"]
}

lanes = { xmm = 0, ymm = 0 }
flags_written = ["C1"]
simd_fp_exceptions = []
other_exceptions = [
  "#IS if stack underflow",
  "#IA if SNaN or unlike-sign infinities",
  "#D if denormal source",
  "#U if result too small",
  "#O if result too large",
  "#P if inexact",
  "#NM if CR0.EM or CR0.TS = 1",
  "#UD if LOCK prefix"
]

semantic_general = """
DEST := DEST + ConvertToDoubleExtendedPrecisionFP(SRC);
"""
