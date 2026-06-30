// Mirror: INC_DEC/FDECSTP.inc

source_isa = "arm64_neon"
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

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
