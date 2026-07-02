// Mirror: KXOR/KXORW.inc
source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "KXOR/KXORW.inc"
x86_handler = "x86_kxorw"
neon_lowering = "arm64_kxorw"
lowering_kind = "arm64_documented_contract"
name = "KXORW"
aliases = []
category = "mask_logical"
feature = "AVX512F"
encodings = [{ opcode = "VEX.L1.0F.W0 47 /r", form = "KXORW k1, k2, k3", op_en = "RVR", vector_length = 0 }]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
