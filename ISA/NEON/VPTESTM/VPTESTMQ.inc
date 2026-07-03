// Mirror: VPTESTM/VPTESTMQ.inc
source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "VPTESTM/VPTESTMQ.inc"
x86_handler = "x86_vptestmq"
neon_lowering = "arm64_vptestmq"
lowering_kind = "arm64_documented_contract"
name = "VPTESTMQ"
aliases = []
category = "test_and_set_mask"
feature = "AVX512F"
encodings = [
  { opcode = "EVEX.128.66.0F38.W1 27 /r", form = "VPTESTMQ k2 {k1}, xmm2, xmm3/m128/m64bcst", op_en = "B", vector_length = 128 },
  { opcode = "EVEX.256.66.0F38.W1 27 /r", form = "VPTESTMQ k2 {k1}, ymm2, ymm3/m256/m64bcst", op_en = "B", vector_length = 256 },
  { opcode = "EVEX.512.66.0F38.W1 27 /r", form = "VPTESTMQ k2 {k1}, zmm2, zmm3/m512/m64bcst", op_en = "B", vector_length = 512 }
]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
