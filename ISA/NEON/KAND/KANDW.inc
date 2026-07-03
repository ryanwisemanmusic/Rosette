// Mirror: KAND/KANDW.inc
source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "KAND/KANDW.inc"
x86_handler = "x86_kandw"
neon_lowering = "arm64_kandw"
lowering_kind = "arm64_documented_contract"
name = "KANDW"
aliases = []
category = "mask_logical"
feature = "AVX512F"
encodings = [{ opcode = "VEX.L1.0F.W0 41 /r", form = "KANDW k1, k2, k3", op_en = "RVR", vector_length = 0 }]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
