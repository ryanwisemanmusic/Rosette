// Mirror: LOGICAL_OR/KORB.inc
source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "LOGICAL_OR/KORB.inc"
x86_handler = "x86_korb"
neon_lowering = "arm64_korb"
lowering_kind = "arm64_documented_contract"
name = "KORB"
aliases = []
category = "mask_register_logical"
feature = "avx512dq"
encodings = [{ opcode = "VEX.L1.66.0F.W0 45 /r", form = "KORB k1, k2, k3", op_en = "RVR", vector_length = 0 }]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
