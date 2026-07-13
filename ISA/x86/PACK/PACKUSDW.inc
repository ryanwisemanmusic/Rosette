// PACK/PACKUSDW.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "PACK/PACKUSDW.inc"
x86_handler = "x86_packusdw"
neon_lowering = "arm64_packusdw"
lowering_kind = "arm64_documented_contract"

name = "PACKUSDW"
aliases = []
category = "pack"
feature = "SSE4_1"
element_type = "integer"
element_size = 0

encodings = [
  { opcode = "66 0F 38 2B /r", form = "PACKUSDW xmm1, xmm2/m128", op_en = "RM", feature = "SSE4_1", vector_length = 128, encoding = "legacy" },
  { opcode = "VEX.128.66.0F38 2B /r", form = "VPACKUSDW xmm1, xmm2, xmm3/m128", op_en = "RVM", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F38 2B /r", form = "VPACKUSDW ymm1, ymm2, ymm3/m256", op_en = "RVM", feature = "AVX2", vector_length = 256, encoding = "vex" },
  { opcode = "EVEX.128.66.0F38.W0 2B /r", form = "VPACKUSDW xmm1{k}{z}, xmm2, xmm3/m128", op_en = "RVM", feature = "AVX512BW+AVX512VL", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F38.W0 2B /r", form = "VPACKUSDW ymm1{k}{z}, ymm2, ymm3/m256", op_en = "RVM", feature = "AVX512BW+AVX512VL", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F38.W0 2B /r", form = "VPACKUSDW zmm1{k}{z}, zmm2, zmm3/m512", op_en = "RVM", feature = "AVX512BW", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  RM = ["ModRM:reg (r,w)", "ModRM:r/m (r)"],
  RVM = ["ModRM:reg (r,w)", "VEX.vvvv (r)", "ModRM:r/m (r)"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
Packs unsigned doubleword integers from two source operands into unsigned word integers in the destination using unsigned saturation. Values exceeding the unsigned word range [0, 65535] are clamped to the nearest boundary. The first source provides the lower dwords and the second source provides the upper dwords.
"""

handler = "x86_packusdw"
jit_lowering = "arm64_packusdw"
fallback = "zig_packusdw"

neon_register_model = "x86 SIMD registers mapped to ARM64 SIMD registers."
neon_flag_model = "No x86 flags affected."
neon_assembly = "// ARM64 NEON: UQXTN/UQXTN2"
neon_notes = ["The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
