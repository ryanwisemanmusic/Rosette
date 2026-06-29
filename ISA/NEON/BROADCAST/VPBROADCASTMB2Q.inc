// Mirror: BROADCAST/VPBROADCASTMB2Q.inc
// Lowering contract mirrors x86 table under arm64_neon ABI.

source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "BROADCAST/VPBROADCASTMB2Q.inc"
x86_handler = "x86_vpbroadcastmb2q"
neon_lowering = "arm64_vpbroadcastmb2q"
lowering_kind = "arm64_documented_contract"

name = "VPBROADCASTMB2Q"
aliases = []
category = "avx512_broadcast"
feature = "avx512cd"

encodings = [
  { opcode = "EVEX.128.F3.0F38.W1 2A /r", form = "VPBROADCASTMB2Q xmm1, k1", op_en = "RM", vector_length = 0 },
  { opcode = "EVEX.256.F3.0F38.W1 2A /r", form = "VPBROADCASTMB2Q ymm1, k1", op_en = "RM", vector_length = 0 },
  { opcode = "EVEX.512.F3.0F38.W1 2A /r", form = "VPBROADCASTMB2Q zmm1, k1", op_en = "RM", vector_length = 0 }
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
