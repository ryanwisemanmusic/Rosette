// Mirror: UNDEF/UD0.inc
source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "UNDEF/UD0.inc"
x86_handler = "x86_ud0"
neon_lowering = "arm64_ud0"
lowering_kind = "arm64_documented_contract"
name = "UD0"
aliases = []
category = "undefined"
feature = "general"
encodings = [{ opcode = "0F FF /r", form = "UD0 r32, r/m32", op_en = "RM", vector_length = 0 }]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
