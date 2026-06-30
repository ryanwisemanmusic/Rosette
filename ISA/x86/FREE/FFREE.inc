// FREE/FFREE.inc
// Source contract: FFREE — Free Floating-Point Register.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "FREE/FFREE.inc"
x86_handler = "x86_ffree"
neon_lowering = "arm64_ffree"
lowering_kind = "arm64_documented_contract"

name = "FFREE"
aliases = []
category = "x87_fpu_register_tag"
feature = "x87"

encodings = [
  { opcode = "DD C0+i", form = "FFREE ST(i)", op_en = "A", feature = "x87", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  A = ["DD C0+i"]
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
Sets the tag in the FPU tag register associated with register ST(i) to empty (11B).
The contents of ST(i) and the FPU stack-top pointer (TOP) are not affected.
"""

handler = "x86_ffree"
jit_lowering = "arm64_ffree"
fallback = "zig_ffree"

neon_register_model = """
FFREE is an x87 FPU register tag manipulation instruction.
No ARM64 NEON equivalent; handled via documented contract.
"""

neon_flag_model = """
C0, C1, C2, C3: undefined.
"""

neon_assembly = """
// NEON lowering: FFREE stub (x87 FPU free register)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
