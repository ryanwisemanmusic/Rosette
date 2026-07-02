// Mirror: UNORDERED/UCOMISD.inc
source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "UNORDERED/UCOMISD.inc"
x86_handler = "x86_ucomisd"
neon_lowering = "arm64_ucomisd"
lowering_kind = "arm64_documented_contract"
name = "UCOMISD"
aliases = ["VUCOMISD"]
category = "compare"
feature = "SSE2"
encodings = [
  { opcode = "66 0F 2E /r", form = "UCOMISD xmm1, xmm2/m64", op_en = "A", vector_length = 0 },
  { opcode = "VEX.LIG.66.0F.WIG 2E /r", form = "VUCOMISD xmm1, xmm2/m64", op_en = "A", vector_length = 0 },
  { opcode = "EVEX.LLIG.66.0F.W1 2E /r", form = "VUCOMISD xmm1, xmm2/m64{sae}", op_en = "B", vector_length = 0 }
]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
