// Mirror: UNORDERED/VUCOMISH.inc
source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "UNORDERED/VUCOMISH.inc"
x86_handler = "x86_vucomish"
neon_lowering = "arm64_vucomish"
lowering_kind = "arm64_documented_contract"
name = "VUCOMISH"
aliases = []
category = "compare"
feature = "AVX512-FP16"
encodings = [{ opcode = "EVEX.LLIG.NP.MAP5.W0 2E /r", form = "VUCOMISH xmm1, xmm2/m16{sae}", op_en = "A", vector_length = 0 }]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
