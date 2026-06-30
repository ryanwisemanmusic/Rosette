// Mirror: PUSH/PUSHF.inc
source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "PUSH/PUSHF.inc"
x86_handler = "x86_pushf"
neon_lowering = "arm64_pushf"
lowering_kind = "arm64_documented_contract"
name = "PUSHF"
aliases = []
category = "stack_push"
feature = "general"
encodings = [{ opcode = "9C", form = "PUSHF", op_en = "ZO", vector_length = 0 }]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
