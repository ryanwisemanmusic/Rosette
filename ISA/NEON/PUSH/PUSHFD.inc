// Mirror: PUSH/PUSHFD.inc
source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "PUSH/PUSHFD.inc"
x86_handler = "x86_pushfd"
neon_lowering = "arm64_pushfd"
lowering_kind = "arm64_documented_contract"
name = "PUSHFD"
aliases = []
category = "stack_push"
feature = "general"
encodings = [{ opcode = "9C", form = "PUSHFD", op_en = "ZO", vector_length = 0 }]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
