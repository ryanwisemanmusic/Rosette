// INC_DEC/FINCSTP.inc
// Source contract: FINCSTP — Increment Stack-Top Pointer.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INC_DEC/FINCSTP.inc"
x86_handler = "x86_fincstp"
neon_lowering = "arm64_fincstp"
lowering_kind = "arm64_documented_contract"

name = "FINCSTP"
aliases = []
category = "x87_fpu_stack_pointer"
feature = "x87"

encodings = [
  { opcode = "D9 F7", form = "FINCSTP", op_en = "ZO", feature = "x87", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = ["N/A", "N/A", "N/A", "N/A"]
}

lanes = { scalar = 1 }
flags_written = []
floating_point_exceptions = []
other_exceptions = [
  "#NM CR0.EM[bit 2] or CR0.TS[bit 3] = 1.",
  "#MF If there is a pending x87 FPU exception.",
  "#UD If the LOCK prefix is used."
]

semantic_general = """
Adds one to the TOP field of the FPU status word (increments the top-of-stack pointer).
If TOP contains 7, it is set to 0.
"""

handler = "x86_fincstp"
jit_lowering = "arm64_fincstp"
fallback = "zig_fincstp"

neon_register_model = """
FINCSTP is an x87 FPU stack pointer instruction. No ARM64 NEON equivalent; handled via documented contract.
"""

neon_flag_model = """
C1 set to 0. C0, C2, C3 undefined.
"""

neon_assembly = """
// NEON lowering: FINCSTP stub (x87 FPU increment stack-top pointer)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
