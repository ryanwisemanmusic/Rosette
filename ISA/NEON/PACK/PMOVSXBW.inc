// PACK/PMOVSXBW.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "PACK/PMOVSXBW.inc"
x86_handler = "x86_pmovsxbw"
neon_lowering = "arm64_pmovsxbw"
lowering_kind = "arm64_documented_contract"

name = "PMOVSXBW"
aliases = []
category = "pack"
feature = "SSE4_1"
element_type = "integer"
element_size = 0

encodings = [
  { opcode = "66 0F 38 20 /r", form = "PMOVSXBW xmm1, xmm2/m64", op_en = "RM", feature = "SSE4_1", vector_length = 128, encoding = "legacy" },
  { opcode = "VEX.128.66.0F38.WIG 20 /r", form = "VPMOVSXBW xmm1, xmm2/m64", op_en = "RM", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F38.WIG 20 /r", form = "VPMOVSXBW ymm1, ymm2/m128", op_en = "RM", feature = "AVX2", vector_length = 256, encoding = "vex" },
  { opcode = "EVEX.128.66.0F38.WIG 20 /r", form = "VPMOVSXBW xmm1{k}{z}, xmm2/m64", op_en = "RM", feature = "AVX512BW+AVX512VL", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F38.WIG 20 /r", form = "VPMOVSXBW ymm1{k}{z}, ymm2/m128", op_en = "RM", feature = "AVX512BW+AVX512VL", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F38.WIG 20 /r", form = "VPMOVSXBW zmm1{k}{z}, ymm2/m256", op_en = "RM", feature = "AVX512BW", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  RM = ["ModRM:reg (w)", "ModRM:r/m (r)"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
Sign-extends packed byte integers from the source operand to word integers in the destination. Reads 8 bytes (m64), 16 bytes (m128), or 32 bytes (m256) from the source and sign-extends each byte to a 16-bit word. The remaining upper elements of the destination are zeroed (128-bit dest from m64) or filled by extension (256-bit dest from m128, 512-bit dest from m256).
"""

handler = "x86_pmovsxbw"
jit_lowering = "arm64_pmovsxbw"
fallback = "zig_pmovsxbw"

neon_register_model = "x86 SIMD registers mapped to ARM64 SIMD registers."
neon_flag_model = "No x86 flags affected."
neon_assembly = "// ARM64 NEON: SXTL/SXTL2 (SSHLL)"
neon_notes = ["The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
