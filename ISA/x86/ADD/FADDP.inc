// ADD/FADDP.inc
// ARM64/NEON translation mirror generated from ISA/x86/ADD/FADDP.inc.
// Source contract: FADDP — Add and Pop (x87 FPU).

semantic = """
DEST := DEST + SRC;
PopRegisterStack;
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ADD/FADDP.inc"
x86_handler = "x86_faddp"
neon_lowering = "arm64_faddp"
lowering_kind = "arm64_scalar"

name = "FADDP"
category = "floating_point_add"
feature = "x87_fpu"
element_type = "f80"

encodings = [
  { opcode = "DE C0+i", form = "FADDP ST(i), ST(0)", op_en = "RR", feature = "x87_FPU", vector_length = 0, encoding = "legacy" },
  { opcode = "DE C1", form = "FADDP", op_en = "ZO", feature = "x87_FPU", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  RR = ["ST(i) (r,w)", "ST(0) (r)"],
  ZO = ["N/A"]
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
DEST := DEST + SRC;
PopRegisterStack;
"""

handler = "x86_faddp"
jit_lowering = "arm64_faddp"
fallback = "zig_faddp"

neon_register_model = """
x87 FPU stack mapped to ARM64 vN registers. FADDP performs addition then stack pop.
"""

neon_flag_model = """
ARM64 FADD does not update flags. x87 C1 flag needs separate tracking if required.
"""

neon_assembly = """
// NEON lowering: fadd dDEST, dSRC; adjust stack pointer
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
