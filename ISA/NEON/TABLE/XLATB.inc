// Mirror: TABLE/XLATB.inc

source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "TABLE/XLATB.inc"
x86_handler = "x86_xlatb"
neon_lowering = "arm64_xlatb"
lowering_kind = "arm64_documented_contract"

name = "XLATB"
aliases = []
category = "table_lookup"
feature = "base"

encodings = [
  { opcode = "D7", form = "XLATB", op_en = "ZO", vector_length = 0 },
  { opcode = "REX.W + D7", form = "XLATB", op_en = "ZO", vector_length = 0 }
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
