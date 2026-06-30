// Mirror: INITIALIZE/FINIT.inc
// Lowering contract mirrors x86 table under arm64_neon ABI.

source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "INITIALIZE/FINIT.inc"
x86_handler = "x86_finit"
neon_lowering = "arm64_finit"
lowering_kind = "arm64_documented_contract"

name = "FINIT"
aliases = []
category = "x87_fpu_initialize"
feature = "x87"

encodings = [
  { opcode = "9B DB E3", form = "FINIT", op_en = "ZO", vector_length = 0 }
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
