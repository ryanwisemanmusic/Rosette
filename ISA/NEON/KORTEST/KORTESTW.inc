// Mirror: KORTEST/KORTESTW.inc
source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "KORTEST/KORTESTW.inc"
x86_handler = "x86_kortestw"
neon_lowering = "arm64_kortestw"
lowering_kind = "arm64_documented_contract"
name = "KORTESTW"
aliases = []
category = "mask_register_test"
feature = "avx512f"
encodings = [{ opcode = "VEX.L0.0F.W0 98 /r", form = "KORTESTW k1, k2", op_en = "RR", vector_length = 0 }]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
