// Mirror: LOGICAL_XNOR/KXNORD.inc

source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "LOGICAL_XNOR/KXNORD.inc"
x86_handler = "x86_kxnord"
neon_lowering = "arm64_kxnord"
lowering_kind = "arm64_documented_contract"

name = "KXNORD"
aliases = []
category = "mask_register_logical"
feature = "avx512bw"

encodings = [
  { opcode = "VEX.L1.66.0F.W1 46 /r", form = "KXNORD k1, k2, k3", op_en = "RVR", vector_length = 0 }
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
