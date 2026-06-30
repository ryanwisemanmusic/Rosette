// Mirror: MEMORY/MFENCE.inc

source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "MEMORY/MFENCE.inc"
x86_handler = "x86_mfence"
neon_lowering = "arm64_mfence"
lowering_kind = "arm64_documented_contract"

name = "MFENCE"
aliases = []
category = "memory_fence"
feature = "sse2"

encodings = [
  { opcode = "NP 0F AE F0", form = "MFENCE", op_en = "ZO", vector_length = 0 }
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
