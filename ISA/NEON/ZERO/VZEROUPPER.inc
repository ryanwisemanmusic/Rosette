// Mirror: ZERO/VZEROUPPER.inc
source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "ZERO/VZEROUPPER.inc"
x86_handler = "x86_vzeroupper"
neon_lowering = "arm64_vzeroupper"
lowering_kind = "arm64_documented_contract"
name = "VZEROUPPER"
aliases = []
category = "register_zero"
feature = "AVX"
encodings = [{ opcode = "VEX.128.0F.WIG 77", form = "VZEROUPPER", op_en = "ZO", vector_length = 128 }]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
