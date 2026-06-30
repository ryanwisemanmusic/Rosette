// Mirror: UNDEF/UD2.inc
source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "UNDEF/UD2.inc"
x86_handler = "x86_ud2"
neon_lowering = "arm64_ud2"
lowering_kind = "arm64_documented_contract"
name = "UD2"
aliases = []
category = "undefined"
feature = "general"
encodings = [{ opcode = "0F 0B", form = "UD2", op_en = "ZO", vector_length = 0 }]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
