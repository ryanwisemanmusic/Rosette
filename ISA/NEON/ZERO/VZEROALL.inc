// Mirror: ZERO/VZEROALL.inc
source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "ZERO/VZEROALL.inc"
x86_handler = "x86_vzeroall"
neon_lowering = "arm64_vzeroall"
lowering_kind = "arm64_documented_contract"
name = "VZEROALL"
aliases = []
category = "register_zero"
feature = "AVX"
encodings = [{ opcode = "VEX.256.0F.WIG 77", form = "VZEROALL", op_en = "ZO", vector_length = 256 }]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
