// Mirror: KORTEST/KORTESTQ.inc
source_isa = "arm64_neon"
target_isa = "arm64_neon"
x86_table = "KORTEST/KORTESTQ.inc"
x86_handler = "x86_kortestq"
neon_lowering = "arm64_kortestq"
lowering_kind = "arm64_documented_contract"
name = "KORTESTQ"
aliases = []
category = "mask_register_test"
feature = "avx512bw"
encodings = [{ opcode = "VEX.L0.0F.W1 98 /r", form = "KORTESTQ k1, k2", op_en = "RR", vector_length = 0 }]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
