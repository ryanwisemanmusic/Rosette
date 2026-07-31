// Mirror: LOGICAL_OR/VPOR.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "LOGICAL_OR/VPOR.inc"
x86_handler = "x86_vpor"
neon_lowering = "arm64_vpor"
lowering_kind = "arm64_documented_contract"
name = "VPOR"
aliases = []
category = "simd_logical"
feature = "avx"
encodings = [
  { opcode = "VEX.128.66.0F.WIG EB /r", form = "VPOR xmm1, xmm2, xmm3/m128", op_en = "B", vector_length = 128 },
  { opcode = "VEX.256.66.0F.WIG EB /r", form = "VPOR ymm1, ymm2, ymm3/m256", op_en = "B", vector_length = 256 }
]

neon_register_model = "VPOR is an AVX/AVX2 bitwise OR instruction."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: VPOR stub"
semantic_general = "Performs a bitwise logical OR on the first and second source operands and stores result in destination."
flags_written = []

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
