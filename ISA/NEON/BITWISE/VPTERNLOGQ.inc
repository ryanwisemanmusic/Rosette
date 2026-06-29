// Mirror: BITWISE/VPTERNLOGQ.inc
// Lowering contract mirrors x86 table under arm64_neon ABI.

source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "BITWISE/VPTERNLOGQ.inc"
x86_handler = "x86_vpternlogq"
neon_lowering = "arm64_vpternlogq"
lowering_kind = "arm64_documented_contract"

name = "VPTERNLOGQ"
aliases = []
category = "avx512_bitwise"
feature = "avx512f"

encodings = [
  { opcode = "EVEX.128.66.0F3A.W1 25 /r ib", form = "VPTERNLOGQ xmm1 {k1}{z}, xmm2, xmm3/m128/m64bcst, imm8", op_en = "A", vector_length = 0 },
  { opcode = "EVEX.256.66.0F3A.W1 25 /r ib", form = "VPTERNLOGQ ymm1 {k1}{z}, ymm2, ymm3/m256/m64bcst, imm8", op_en = "A", vector_length = 0 },
  { opcode = "EVEX.512.66.0F3A.W1 25 /r ib", form = "VPTERNLOGQ zmm1 {k1}{z}, zmm2, zmm3/m512/m64bcst, imm8", op_en = "A", vector_length = 0 }
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
