// Mirror: PAND/PAND.inc
source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "PAND/PAND.inc"
x86_handler = "x86_pand"
neon_lowering = "arm64_pand"
lowering_kind = "arm64_documented_contract"
name = "PAND"
aliases = []
category = "bitwise_logical"
feature = "MMX"
encodings = [
  { opcode = "NP 0F DB /r", form = "PAND mm, mm/m64", op_en = "A", vector_length = 0 },
  { opcode = "66 0F DB /r", form = "PAND xmm1, xmm2/m128", op_en = "A", vector_length = 128 }
]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
