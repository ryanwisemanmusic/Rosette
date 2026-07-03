// Mirror: KAND/KANDQ.inc
source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "KAND/KANDQ.inc"
x86_handler = "x86_kandq"
neon_lowering = "arm64_kandq"
lowering_kind = "arm64_documented_contract"
name = "KANDQ"
aliases = []
category = "mask_logical"
feature = "AVX512BW"
encodings = [{ opcode = "VEX.L1.0F.W1 41 /r", form = "KANDQ k1, k2, k3", op_en = "RVR", vector_length = 0 }]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
