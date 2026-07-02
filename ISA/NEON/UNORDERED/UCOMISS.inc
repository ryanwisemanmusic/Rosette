// Mirror: UNORDERED/UCOMISS.inc
source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "UNORDERED/UCOMISS.inc"
x86_handler = "x86_ucomiss"
neon_lowering = "arm64_ucomiss"
lowering_kind = "arm64_documented_contract"
name = "UCOMISS"
aliases = ["VUCOMISS"]
category = "compare"
feature = "SSE"
encodings = [
  { opcode = "NP 0F 2E /r", form = "UCOMISS xmm1, xmm2/m32", op_en = "A", vector_length = 0 },
  { opcode = "VEX.LIG.0F.WIG 2E /r", form = "VUCOMISS xmm1, xmm2/m32", op_en = "A", vector_length = 0 },
  { opcode = "EVEX.LLIG.0F.W0 2E /r", form = "VUCOMISS xmm1, xmm2/m32{sae}", op_en = "B", vector_length = 0 }
]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
