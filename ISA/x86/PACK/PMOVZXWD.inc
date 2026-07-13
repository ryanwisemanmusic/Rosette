// PACK/PMOVZXWD.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "PACK/PMOVZXWD.inc"
x86_handler = "x86_pmovzxwd"
neon_lowering = "arm64_pmovzxwd"
lowering_kind = "arm64_documented_contract"

name = "PMOVZXWD"
aliases = []
category = "pack"
feature = "SSE4_1"
element_type = "integer"
element_size = 0

encodings = [
  { opcode = "66 0F 38 33 /r", form = "PMOVZXWD xmm1, xmm2/m64", op_en = "RM", feature = "SSE4_1", vector_length = 128, encoding = "legacy" },
  { opcode = "VEX.128.66.0F38.WIG 33 /r", form = "VPMOVZXWD xmm1, xmm2/m64", op_en = "RM", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F38.WIG 33 /r", form = "VPMOVZXWD ymm1, ymm2/m128", op_en = "RM", feature = "AVX2", vector_length = 256, encoding = "vex" },
  { opcode = "EVEX.128.66.0F38.WIG 33 /r", form = "VPMOVZXWD xmm1{k}{z}, xmm2/m64", op_en = "RM", feature = "AVX512F+AVX512VL", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F38.WIG 33 /r", form = "VPMOVZXWD ymm1{k}{z}, ymm2/m128", op_en = "RM", feature = "AVX512F+AVX512VL", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F38.WIG 33 /r", form = "VPMOVZXWD zmm1{k}{z}, ymm2/m256", op_en = "RM", feature = "AVX512F", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  RM = ["ModRM:reg (w)", "ModRM:r/m (r)"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
Zero-extends packed word integers from the source operand to doubleword integers in the destination. Reads 4 words (m64), 8 words (m128), or 16 words (m256) from the source and zero-extends each word to a 32-bit doubleword. The remaining upper elements of the destination are zeroed or filled by extension.
"""

handler = "x86_pmovzxwd"
jit_lowering = "arm64_pmovzxwd"
fallback = "zig_pmovzxwd"

neon_register_model = "x86 SIMD registers mapped to ARM64 SIMD registers."
neon_flag_model = "No x86 flags affected."
neon_assembly = "// ARM64 NEON: UXTL/UXTL2"
neon_notes = ["The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
