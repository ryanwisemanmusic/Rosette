// Mirror: PAND/VPANDD.inc
source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "PAND/VPANDD.inc"
x86_handler = "x86_vpandd"
neon_lowering = "arm64_vpandd"
lowering_kind = "arm64_documented_contract"
name = "VPANDD"
aliases = []
category = "bitwise_logical"
feature = "AVX512F"
encodings = [
  { opcode = "EVEX.128.66.0F.W0 DB /r", form = "VPANDD xmm1 {k1}{z}, xmm2, xmm3/m128/m32bcst", op_en = "C", vector_length = 128 },
  { opcode = "EVEX.256.66.0F.W0 DB /r", form = "VPANDD ymm1 {k1}{z}, ymm2, ymm3/m256/m32bcst", op_en = "C", vector_length = 256 },
  { opcode = "EVEX.512.66.0F.W0 DB /r", form = "VPANDD zmm1 {k1}{z}, zmm2, zmm3/m512/m32bcst", op_en = "C", vector_length = 512 }
]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
