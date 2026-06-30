// Mirror: GET/XGETBV.inc
// Lowering contract mirrors x86 table under arm64_neon ABI.

source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "GET/XGETBV.inc"
x86_handler = "x86_xgetbv"
neon_lowering = "arm64_xgetbv"
lowering_kind = "arm64_documented_contract"

name = "XGETBV"
aliases = []
category = "xcr_read"
feature = "xsave"

encodings = [
  { opcode = "NP 0F 01 D0", form = "XGETBV", op_en = "ZO", vector_length = 0 }
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
