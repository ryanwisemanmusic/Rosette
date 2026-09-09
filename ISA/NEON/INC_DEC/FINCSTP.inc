// Mirror: INC_DEC/FINCSTP.inc

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
  { opcode = "D9 F7", form = "FINCSTP", op_en = "ZO", vector_length = 0 }
]

semantic_general = """
Adds one to the TOP field of the FPU status word (increments the top-of-stack pointer).
If TOP contains 7, it is set to 0.
"""

flags_written = []

neon_register_model = """
FINCSTP is an x87 FPU stack-pointer instruction modeled in the software x87 state.
"""

neon_flag_model = """
FINCSTP does not architecturally write condition flags; pending x87 status remains explicit.
"""

neon_assembly = """
// ARM64 lowering: update the emulated x87 TOP field.
"""

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
