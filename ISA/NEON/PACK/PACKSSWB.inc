// PACK/PACKSSWB.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "PACK/PACKSSWB.inc"
x86_handler = "x86_packsswb"
neon_lowering = "arm64_packsswb"
lowering_kind = "arm64_documented_contract"

name = "PACKSSWB"
aliases = []
category = "pack"
feature = "MMX"
element_type = "integer"
element_size = 0

encodings = [
  { opcode = "NP 0F 63 /r", form = "PACKSSWB mm, mm/m64", op_en = "RM", feature = "MMX", vector_length = 0, encoding = "legacy" },
  { opcode = "66 0F 63 /r", form = "PACKSSWB xmm1, xmm2/m128", op_en = "RM", feature = "SSE2", vector_length = 128, encoding = "legacy" },
  { opcode = "VEX.128.66.0F.WIG 63 /r", form = "VPACKSSWB xmm1, xmm2, xmm3/m128", op_en = "RVM", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F.WIG 63 /r", form = "VPACKSSWB ymm1, ymm2, ymm3/m256", op_en = "RVM", feature = "AVX2", vector_length = 256, encoding = "vex" },
  { opcode = "EVEX.128.66.0F.WIG 63 /r", form = "VPACKSSWB xmm1{k}{z}, xmm2, xmm3/m128", op_en = "RVM", feature = "AVX512BW+AVX512VL", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F.WIG 63 /r", form = "VPACKSSWB ymm1{k}{z}, ymm2, ymm3/m256", op_en = "RVM", feature = "AVX512BW+AVX512VL", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F.WIG 63 /r", form = "VPACKSSWB zmm1{k}{z}, zmm2, zmm3/m512", op_en = "RVM", feature = "AVX512BW", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  RM = ["ModRM:reg (r,w)", "ModRM:r/m (r)"],
  RVM = ["ModRM:reg (r,w)", "VEX.vvvv (r)", "ModRM:r/m (r)"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
Packs signed word integers from two source operands into signed byte integers in the destination using signed saturation. Values exceeding the signed byte range [-128, 127] are clamped to the nearest boundary. The first source provides the lower words and the second source provides the upper words.
"""

handler = "x86_packsswb"
jit_lowering = "arm64_packsswb"
fallback = "zig_packsswb"

neon_register_model = "x86 SIMD registers mapped to ARM64 SIMD registers."
neon_flag_model = "No x86 flags affected."
neon_assembly = "// ARM64 NEON: SQXTN/SQXTN2"
neon_notes = ["The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
