// Mirror: INC_DEC/FINCSTP.inc

source_isa = "arm64_neon"
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

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
