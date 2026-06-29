// Mirror: ALIGN/VALIGND.inc
// Lowering contract mirrors x86 table under arm64_neon ABI.

source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "ALIGN/VALIGND.inc"
x86_handler = "x86_valignd"
neon_lowering = "arm64_valignd"
lowering_kind = "arm64_documented_contract"

name = "VALIGND"
aliases = []
category = "avx512_align"
feature = "avx512f"

encodings = [
  { opcode = "EVEX.128.66.0F3A.W0 03 /r ib", form = "VALIGND xmm1 {k1}{z}, xmm2, xmm3/m128/m32bcst, imm8", op_en = "A", vector_length = 0 },
  { opcode = "EVEX.256.66.0F3A.W0 03 /r ib", form = "VALIGND ymm1 {k1}{z}, ymm2, ymm3/m256/m32bcst, imm8", op_en = "A", vector_length = 0 },
  { opcode = "EVEX.512.66.0F3A.W0 03 /r ib", form = "VALIGND zmm1 {k1}{z}, zmm2, zmm3/m512/m32bcst, imm8", op_en = "A", vector_length = 0 }
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
