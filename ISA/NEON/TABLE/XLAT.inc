// Mirror: TABLE/XLAT.inc

source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "TABLE/XLAT.inc"
x86_handler = "x86_xlat"
neon_lowering = "arm64_xlat"
lowering_kind = "arm64_documented_contract"

name = "XLAT"
aliases = []
category = "table_lookup"
feature = "base"

encodings = [
  { opcode = "D7", form = "XLAT m8", op_en = "ZO", vector_length = 0 }
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
