// Mirror: LOGICAL_XNOR/KXNORW.inc

source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "LOGICAL_XNOR/KXNORW.inc"
x86_handler = "x86_kxnorw"
neon_lowering = "arm64_kxnorw"
lowering_kind = "arm64_documented_contract"

name = "KXNORW"
aliases = []
category = "mask_register_logical"
feature = "avx512f"

encodings = [
  { opcode = "VEX.L1.0F.W0 46 /r", form = "KXNORW k1, k2, k3", op_en = "RVR", vector_length = 0 }
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
