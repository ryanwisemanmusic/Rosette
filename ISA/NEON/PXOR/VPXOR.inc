// Mirror: PXOR/VPXOR.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "PXOR/VPXOR.inc"
x86_handler = "x86_vpxor"
neon_lowering = "arm64_vpxor"
lowering_kind = "arm64_documented_contract"
name = "VPXOR"
aliases = []
category = "bitwise_logical"
feature = "AVX"
encodings = [
  { opcode = "VEX.128.66.0F.WIG EF /r", form = "VPXOR xmm1, xmm2, xmm3/m128", op_en = "B", vector_length = 128 },
  { opcode = "VEX.256.66.0F.WIG EF /r", form = "VPXOR ymm1, ymm2, ymm3/m256", op_en = "B", vector_length = 256 }
]

neon_register_model = "VPXOR is an x86 packed integer logical XOR. NEON lowering via bitwise EOR."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: VPXOR -> EOR (bitwise XOR)"
semantic_general = """
Bitwise XOR of packed integer operands. 128-bit (AVX) and 256-bit (AVX2) VEX forms.
"""
flags_written = []

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape"]
