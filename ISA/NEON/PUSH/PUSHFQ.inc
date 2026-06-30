// Mirror: PUSH/PUSHFQ.inc
source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "PUSH/PUSHFQ.inc"
x86_handler = "x86_pushfq"
neon_lowering = "arm64_pushfq"
lowering_kind = "arm64_documented_contract"
name = "PUSHFQ"
aliases = []
category = "stack_push"
feature = "general"
encodings = [{ opcode = "9C", form = "PUSHFQ", op_en = "ZO", vector_length = 0 }]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
