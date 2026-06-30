// Mirror: LOGICAL_OR/POR.inc
source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "LOGICAL_OR/POR.inc"
x86_handler = "x86_por"
neon_lowering = "arm64_por"
lowering_kind = "arm64_documented_contract"
name = "POR"
aliases = []
category = "simd_logical"
feature = "mmx"
encodings = [
  { opcode = "NP 0F EB /r", form = "POR mm, mm/m64", op_en = "A", vector_length = 64 },
  { opcode = "66 0F EB /r", form = "POR xmm1, xmm2/m128", op_en = "A", vector_length = 128 }
]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
