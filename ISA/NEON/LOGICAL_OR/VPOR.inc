// Mirror: LOGICAL_OR/VPOR.inc
source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "LOGICAL_OR/VPOR.inc"
x86_handler = "x86_vpor"
neon_lowering = "arm64_vpor"
lowering_kind = "arm64_documented_contract"
name = "VPOR"
aliases = []
category = "simd_logical"
feature = "avx"
encodings = [
  { opcode = "VEX.128.66.0F.WIG EB /r", form = "VPOR xmm1, xmm2, xmm3/m128", op_en = "B", vector_length = 128 },
  { opcode = "VEX.256.66.0F.WIG EB /r", form = "VPOR ymm1, ymm2, ymm3/m256", op_en = "B", vector_length = 256 }
]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
