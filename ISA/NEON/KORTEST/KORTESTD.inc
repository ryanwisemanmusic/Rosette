// Mirror: KORTEST/KORTESTD.inc
source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "KORTEST/KORTESTD.inc"
x86_handler = "x86_kortestd"
neon_lowering = "arm64_kortestd"
lowering_kind = "arm64_documented_contract"
name = "KORTESTD"
aliases = []
category = "mask_register_test"
feature = "avx512bw"
encodings = [{ opcode = "VEX.L0.66.0F.W1 98 /r", form = "KORTESTD k1, k2", op_en = "RR", vector_length = 0 }]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
