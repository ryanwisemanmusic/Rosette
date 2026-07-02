// Mirror: PXOR/VPXORQ.inc
source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "PXOR/VPXORQ.inc"
x86_handler = "x86_vpxorq"
neon_lowering = "arm64_vpxorq"
lowering_kind = "arm64_documented_contract"
name = "VPXORQ"
aliases = []
category = "bitwise_logical"
feature = "AVX512F"
encodings = [
  { opcode = "EVEX.128.66.0F.W1 EF /r", form = "VPXORQ xmm1 {k1}{z}, xmm2, xmm3/m128/m64bcst", op_en = "C", vector_length = 128 },
  { opcode = "EVEX.256.66.0F.W1 EF /r", form = "VPXORQ ymm1 {k1}{z}, ymm2, ymm3/m256/m64bcst", op_en = "C", vector_length = 256 },
  { opcode = "EVEX.512.66.0F.W1 EF /r", form = "VPXORQ zmm1 {k1}{z}, zmm2, zmm3/m512/m64bcst", op_en = "C", vector_length = 512 }
]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
