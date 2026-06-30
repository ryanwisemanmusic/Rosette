// Mirror: DEP/PDEP.inc
// Lowering contract mirrors x86 table under arm64_neon ABI.

source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "DEP/PDEP.inc"
x86_handler = "x86_pdep"
neon_lowering = "arm64_pdep"
lowering_kind = "arm64_documented_contract"

name = "PDEP"
aliases = []
category = "bmi2_bit_deposit"
feature = "bmi2"

encodings = [
  { opcode = "VEX.LZ.F2.0F38.W0 F5 /r", form = "PDEP r32a, r32b, r/m32", op_en = "RVM", vector_length = 0 },
  { opcode = "VEX.LZ.F2.0F38.W1 F5 /r", form = "PDEP r64a, r64b, r/m64", op_en = "RVM", vector_length = 0 }
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
