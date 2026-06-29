// Mirror: BROADCAST/VPBROADCASTMW2D.inc
// Lowering contract mirrors x86 table under arm64_neon ABI.

source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "BROADCAST/VPBROADCASTMW2D.inc"
x86_handler = "x86_vpbroadcastmw2d"
neon_lowering = "arm64_vpbroadcastmw2d"
lowering_kind = "arm64_documented_contract"

name = "VPBROADCASTMW2D"
aliases = []
category = "avx512_broadcast"
feature = "avx512cd"

encodings = [
  { opcode = "EVEX.128.F3.0F38.W0 3A /r", form = "VPBROADCASTMW2D xmm1, k1", op_en = "RM", vector_length = 0 },
  { opcode = "EVEX.256.F3.0F38.W0 3A /r", form = "VPBROADCASTMW2D ymm1, k1", op_en = "RM", vector_length = 0 },
  { opcode = "EVEX.512.F3.0F38.W0 3A /r", form = "VPBROADCASTMW2D zmm1, k1", op_en = "RM", vector_length = 0 }
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
