// Mirror: PXOR/VPXOR.inc
source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "PXOR/VPXOR.inc"
x86_handler = "x86_vpxor"
neon_lowering = "arm64_vpxor"
lowering_kind = "arm64_documented_contract"
name = "VPXOR"
aliases = []
category = "bitwise_logical"
feature = "AVX"
encodings = [
  { opcode = "VEX.128.66.0F.WIG EF /r", form = "VPXOR xmm1, xmm2, xmm3/m128", op_en = "B", vector_length = 128 },
  { opcode = "VEX.256.66.0F.WIG EF /r", form = "VPXOR ymm1, ymm2, ymm3/m256", op_en = "B", vector_length = 256 }
]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
