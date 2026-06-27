// ADD/FIADD.inc
// ARM64/NEON translation mirror generated from ISA/x86/ADD/FIADD.inc.
// Source contract: FIADD — Add Integer to FPU.

semantic = """
DEST := DEST + ConvertToDoubleExtendedPrecisionFP(SRC)
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ADD/FIADD.inc"
x86_handler = "x86_fiadd"
neon_lowering = "arm64_fiadd"
lowering_kind = "arm64_scalar"

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

handler = "x86_fiadd"
jit_lowering = "arm64_fiadd"
fallback = "zig_fiadd"

neon_register_model = """
x87 FPU stack mapped to ARM64 vN registers. Integer source must be converted to extended-precision float before add.
"""

neon_flag_model = """
ARM64 FADD does not update flags. x87 C1 flag needs separate tracking if required.
"""

neon_assembly = """
// NEON lowering: scvtf dTMP, sSRC; fadd dDEST, dDEST, dTMP
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
