// Mirror: KXOR/KXORQ.inc
source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "KXOR/KXORQ.inc"
x86_handler = "x86_kxorq"
neon_lowering = "arm64_kxorq"
lowering_kind = "arm64_documented_contract"
name = "KXORQ"
aliases = []
category = "mask_logical"
feature = "AVX512BW"
encodings = [{ opcode = "VEX.L1.0F.W1 47 /r", form = "KXORQ k1, k2, k3", op_en = "RVR", vector_length = 0 }]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
