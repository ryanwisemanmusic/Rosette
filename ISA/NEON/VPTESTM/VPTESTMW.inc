// Mirror: VPTESTM/VPTESTMW.inc
source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "VPTESTM/VPTESTMW.inc"
x86_handler = "x86_vptestmw"
neon_lowering = "arm64_vptestmw"
lowering_kind = "arm64_documented_contract"
name = "VPTESTMW"
aliases = []
category = "test_and_set_mask"
feature = "AVX512BW"
encodings = [
  { opcode = "EVEX.128.66.0F38.W1 26 /r", form = "VPTESTMW k2 {k1}, xmm2, xmm3/m128", op_en = "A", vector_length = 128 },
  { opcode = "EVEX.256.66.0F38.W1 26 /r", form = "VPTESTMW k2 {k1}, ymm2, ymm3/m256", op_en = "A", vector_length = 256 },
  { opcode = "EVEX.512.66.0F38.W1 26 /r", form = "VPTESTMW k2 {k1}, zmm2, zmm3/m512", op_en = "A", vector_length = 512 }
]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
