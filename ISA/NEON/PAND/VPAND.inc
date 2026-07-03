// Mirror: PAND/VPAND.inc
source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "PAND/VPAND.inc"
x86_handler = "x86_vpand"
neon_lowering = "arm64_vpand"
lowering_kind = "arm64_documented_contract"
name = "VPAND"
aliases = []
category = "bitwise_logical"
feature = "AVX"
encodings = [
  { opcode = "VEX.128.66.0F.WIG DB /r", form = "VPAND xmm1, xmm2, xmm3/m128", op_en = "B", vector_length = 128 },
  { opcode = "VEX.256.66.0F.WIG DB /r", form = "VPAND ymm1, ymm2, ymm3/m256", op_en = "B", vector_length = 256 }
]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
