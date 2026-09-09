// Mirror: INC_DEC/FDECSTP.inc

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
  { opcode = "D9 F6", form = "FDECSTP", op_en = "ZO", vector_length = 0 }
]

semantic_general = """
Subtracts one from the TOP field of the FPU status word (decrements the top-of-stack pointer).
If TOP contains 0, it is set to 7.
"""

flags_written = []

neon_register_model = """
FDECSTP is an x87 FPU stack-pointer instruction modeled in the software x87 state.
"""

neon_flag_model = """
FDECSTP does not architecturally write condition flags; pending x87 status remains explicit.
"""

neon_assembly = """
// ARM64 lowering: update the emulated x87 TOP field.
"""

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
