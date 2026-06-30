// Mirror: LOGICAL_XNOR/KXNORB.inc

source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "LOGICAL_XNOR/KXNORB.inc"
x86_handler = "x86_kxnorb"
neon_lowering = "arm64_kxnorb"
lowering_kind = "arm64_documented_contract"

name = "KXNORB"
aliases = []
category = "mask_register_logical"
feature = "avx512dq"

encodings = [
  { opcode = "VEX.L1.66.0F.W0 46 /r", form = "KXNORB k1, k2, k3", op_en = "RVR", vector_length = 0 }
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
