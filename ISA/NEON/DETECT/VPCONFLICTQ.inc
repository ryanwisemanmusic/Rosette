// Mirror: DETECT/VPCONFLICTQ.inc

source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "DETECT/VPCONFLICTQ.inc"
x86_handler = "x86_vpconflictq"
neon_lowering = "arm64_vpconflictq"
lowering_kind = "arm64_documented_contract"

name = "VPCONFLICTQ"
aliases = []
category = "vector_conflict_detection"
feature = "avx512cd"

encodings = [
  { opcode = "EVEX.128.66.0F38.W1 C4 /r", form = "VPCONFLICTQ xmm1 {k1}{z}, xmm2/m128/m64bcst", op_en = "A", vector_length = 128 },
  { opcode = "EVEX.256.66.0F38.W1 C4 /r", form = "VPCONFLICTQ ymm1 {k1}{z}, ymm2/m256/m64bcst", op_en = "A", vector_length = 256 },
  { opcode = "EVEX.512.66.0F38.W1 C4 /r", form = "VPCONFLICTQ zmm1 {k1}{z}, zmm2/m512/m64bcst", op_en = "A", vector_length = 512 }
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
