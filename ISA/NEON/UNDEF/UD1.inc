// Mirror: UNDEF/UD1.inc
source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "UNDEF/UD1.inc"
x86_handler = "x86_ud1"
neon_lowering = "arm64_ud1"
lowering_kind = "arm64_documented_contract"
name = "UD1"
aliases = []
category = "undefined"
feature = "general"
encodings = [{ opcode = "0F B9 /r", form = "UD1 r32, r/m32", op_en = "RM", vector_length = 0 }]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
