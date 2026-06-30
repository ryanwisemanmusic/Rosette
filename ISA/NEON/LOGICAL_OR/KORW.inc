// Mirror: LOGICAL_OR/KORW.inc
source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "LOGICAL_OR/KORW.inc"
x86_handler = "x86_korw"
neon_lowering = "arm64_korw"
lowering_kind = "arm64_documented_contract"
name = "KORW"
aliases = []
category = "mask_register_logical"
feature = "avx512f"
encodings = [{ opcode = "VEX.L1.0F.W0 45 /r", form = "KORW k1, k2, k3", op_en = "RVR", vector_length = 0 }]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
