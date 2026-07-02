// Mirror: KXOR/KXORB.inc
source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "KXOR/KXORB.inc"
x86_handler = "x86_kxorb"
neon_lowering = "arm64_kxorb"
lowering_kind = "arm64_documented_contract"
name = "KXORB"
aliases = []
category = "mask_logical"
feature = "AVX512DQ"
encodings = [{ opcode = "VEX.L1.66.0F.W0 47 /r", form = "KXORB k1, k2, k3", op_en = "RVR", vector_length = 0 }]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
