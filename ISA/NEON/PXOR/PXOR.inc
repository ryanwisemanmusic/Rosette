// Mirror: PXOR/PXOR.inc
source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "PXOR/PXOR.inc"
x86_handler = "x86_pxor"
neon_lowering = "arm64_pxor"
lowering_kind = "arm64_documented_contract"
name = "PXOR"
aliases = []
category = "bitwise_logical"
feature = "MMX"
encodings = [
  { opcode = "NP 0F EF /r", form = "PXOR mm, mm/m64", op_en = "A", vector_length = 0 },
  { opcode = "66 0F EF /r", form = "PXOR xmm1, xmm2/m128", op_en = "A", vector_length = 128 }
]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
