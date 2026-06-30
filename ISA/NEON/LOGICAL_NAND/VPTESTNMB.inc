// Mirror: LOGICAL_NAND/VPTESTNMB.inc

source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "LOGICAL_NAND/VPTESTNMB.inc"
x86_handler = "x86_vptestnmb"
neon_lowering = "arm64_vptestnmb"
lowering_kind = "arm64_documented_contract"

name = "VPTESTNMB"
aliases = []
category = "mask_generation_logical_nand"
feature = "avx512bw"

encodings = [
  { opcode = "EVEX.128.F3.0F38.W0 26 /r", form = "VPTESTNMB k2 {k1}, xmm2, xmm3/m128", op_en = "A", vector_length = 128 },
  { opcode = "EVEX.256.F3.0F38.W0 26 /r", form = "VPTESTNMB k2 {k1}, ymm2, ymm3/m256", op_en = "A", vector_length = 256 },
  { opcode = "EVEX.512.F3.0F38.W0 26 /r", form = "VPTESTNMB k2 {k1}, zmm2, zmm3/m512", op_en = "A", vector_length = 512 }
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
