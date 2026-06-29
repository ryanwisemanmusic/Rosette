// Mirror: AVERAGE/PAVGB.inc
// Lowering contract mirrors x86 table under arm64_neon ABI.

source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "AVERAGE/PAVGB.inc"
x86_handler = "x86_pavgb"
neon_lowering = "arm64_pavgb"
lowering_kind = "arm64_documented_contract"

name = "PAVGB"
aliases = ["VPAVGB"]
category = "simd_average"
feature = "sse"

encodings = [
  { opcode = "NP 0F E0 /r", form = "PAVGB mm1, mm2/m64", op_en = "A", vector_length = 0 },
  { opcode = "66 0F E0 /r", form = "PAVGB xmm1, xmm2/m128", op_en = "A", vector_length = 0 },
  { opcode = "VEX.128.66.0F.WIG E0 /r", form = "VPAVGB xmm1, xmm2, xmm3/m128", op_en = "B", vector_length = 0 },
  { opcode = "VEX.256.66.0F.WIG E0 /r", form = "VPAVGB ymm1, ymm2, ymm3/m256", op_en = "B", vector_length = 0 },
  { opcode = "EVEX.128.66.0F.WIG E0 /r", form = "VPAVGB xmm1 {k1}{z}, xmm2, xmm3/m128", op_en = "C", vector_length = 0 },
  { opcode = "EVEX.256.66.0F.WIG E0 /r", form = "VPAVGB ymm1 {k1}{z}, ymm2, ymm3/m256", op_en = "C", vector_length = 0 },
  { opcode = "EVEX.512.66.0F.WIG E0 /r", form = "VPAVGB zmm1 {k1}{z}, zmm2, zmm3/m512", op_en = "C", vector_length = 0 }
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
