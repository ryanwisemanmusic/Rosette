// INC_DEC/FDECSTP.inc
// Source contract: FDECSTP — Decrement Stack-Top Pointer.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INC_DEC/FDECSTP.inc"
x86_handler = "x86_fdecstp"
neon_lowering = "arm64_fdecstp"
lowering_kind = "arm64_documented_contract"

name = "FDECSTP"
aliases = []
category = "x87_fpu_stack_pointer"
feature = "x87"

encodings = [
  { opcode = "D9 F6", form = "FDECSTP", op_en = "ZO", feature = "x87", vector_length = 0, encoding = "legacy" }
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
Subtracts one from the TOP field of the FPU status word (decrements the top-of-stack pointer).
If TOP contains 0, it is set to 7.
"""

handler = "x86_fdecstp"
jit_lowering = "arm64_fdecstp"
fallback = "zig_fdecstp"

neon_register_model = """
FDECSTP is an x87 FPU stack pointer instruction. No ARM64 NEON equivalent; handled via documented contract.
"""

neon_flag_model = """
C1 set to 0. C0, C2, C3 undefined.
"""

neon_assembly = """
// NEON lowering: FDECSTP stub (x87 FPU decrement stack-top pointer)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
