// PACK/PSIGNW.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "PACK/PSIGNW.inc"
x86_handler = "x86_psignw"
neon_lowering = "arm64_psignw"
lowering_kind = "arm64_documented_contract"

name = "PSIGNW"
aliases = []
category = "pack"
feature = "MMX"
element_type = "integer"
element_size = 0

encodings = [
  { opcode = "NP 0F 38 09 /r", form = "PSIGNW mm1, mm2/m64", op_en = "RM", feature = "MMX", vector_length = 0, encoding = "legacy" },
  { opcode = "66 0F 38 09 /r", form = "PSIGNW xmm1, xmm2/m128", op_en = "RM", feature = "SSSE3", vector_length = 128, encoding = "legacy" },
  { opcode = "VEX.128.66.0F38.WIG 09 /r", form = "VPSIGNW xmm1, xmm2, xmm3/m128", op_en = "RVM", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F38.WIG 09 /r", form = "VPSIGNW ymm1, ymm2, ymm3/m256", op_en = "RVM", feature = "AVX2", vector_length = 256, encoding = "vex" }
]

operand_encoding = {
  RM = ["ModRM:reg (r,w)", "ModRM:r/m (r)"],
  RVM = ["ModRM:reg (r,w)", "VEX.vvvv (r)", "ModRM:r/m (r)"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
Negates each signed word integer in the destination operand if the corresponding signed word integer in the source operand is negative. If the source word is zero, the destination word is set to zero. If the source word is positive, the destination word is unchanged. For VEX forms, the first source operand (VEX.vvvv) provides the data to be conditionally negated.
"""

handler = "x86_psignw"
jit_lowering = "arm64_psignw"
fallback = "zig_psignw"

neon_register_model = "x86 SIMD registers mapped to ARM64 SIMD registers."
neon_flag_model = "No x86 flags affected."
neon_assembly = "// ARM64 NEON: sequence of compare + negate + select"
neon_notes = ["The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
