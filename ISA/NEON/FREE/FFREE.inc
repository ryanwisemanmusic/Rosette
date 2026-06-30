// Mirror: FREE/FFREE.inc
// Lowering contract mirrors x86 table under arm64_neon ABI.

source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "FREE/FFREE.inc"
x86_handler = "x86_ffree"
neon_lowering = "arm64_ffree"
lowering_kind = "arm64_documented_contract"

name = "FFREE"
aliases = []
category = "x87_fpu_register_tag"
feature = "x87"

encodings = [
  { opcode = "DD C0+i", form = "FFREE ST(i)", op_en = "A", vector_length = 0 }
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
