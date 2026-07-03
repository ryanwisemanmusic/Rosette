// Mirror: KAND/KANDD.inc
source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "KAND/KANDD.inc"
x86_handler = "x86_kandd"
neon_lowering = "arm64_kandd"
lowering_kind = "arm64_documented_contract"
name = "KANDD"
aliases = []
category = "mask_logical"
feature = "AVX512BW"
encodings = [{ opcode = "VEX.L1.66.0F.W1 41 /r", form = "KANDD k1, k2, k3", op_en = "RVR", vector_length = 0 }]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
