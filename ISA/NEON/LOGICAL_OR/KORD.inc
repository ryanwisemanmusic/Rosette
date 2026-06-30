// Mirror: LOGICAL_OR/KORD.inc
source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "LOGICAL_OR/KORD.inc"
x86_handler = "x86_kord"
neon_lowering = "arm64_kord"
lowering_kind = "arm64_documented_contract"
name = "KORD"
aliases = []
category = "mask_register_logical"
feature = "avx512bw"
encodings = [{ opcode = "VEX.L1.66.0F.W1 45 /r", form = "KORD k1, k2, k3", op_en = "RVR", vector_length = 0 }]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
