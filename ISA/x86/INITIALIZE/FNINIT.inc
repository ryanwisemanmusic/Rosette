// INITIALIZE/FNINIT.inc
// Source contract: FNINIT — Initialize Floating-Point Unit (without exception check).

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INITIALIZE/FNINIT.inc"
x86_handler = "x86_fninit"
neon_lowering = "arm64_fninit"
lowering_kind = "arm64_documented_contract"

name = "FNINIT"
aliases = []
category = "x87_fpu_initialize"
feature = "x87"

encodings = [
  { opcode = "DB E3", form = "FNINIT", op_en = "ZO", feature = "x87", vector_length = 0, encoding = "legacy" }
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
Sets the FPU control, status, tag, instruction pointer, and data pointer registers to their default states.
The FNINIT instruction does not check for pending unmasked floating-point exceptions before performing the initialization.
"""

handler = "x86_fninit"
jit_lowering = "arm64_fninit"
fallback = "zig_fninit"

neon_register_model = """
FNINIT is an x87 FPU initialization instruction. No ARM64 NEON equivalent; handled via documented contract.
"""

neon_flag_model = """
C0, C1, C2, C3: set to 0.
"""

neon_assembly = """
// NEON lowering: FNINIT stub (x87 FPU initialize without exception check)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
