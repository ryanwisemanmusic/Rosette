// PACK/PSHUFB.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "PACK/PSHUFB.inc"
x86_handler = "x86_pshufb"
neon_lowering = "arm64_pshufb"
lowering_kind = "arm64_documented_contract"

name = "PSHUFB"
aliases = []
category = "pack"
feature = "SSSE3"
element_type = "integer"
element_size = 0

encodings = [
  { opcode = "NP 0F 38 00 /r", form = "PSHUFB mm1, mm2/m64", op_en = "RM", feature = "SSSE3", vector_length = 0, encoding = "legacy" },
  { opcode = "66 0F 38 00 /r", form = "PSHUFB xmm1, xmm2/m128", op_en = "RM", feature = "SSSE3", vector_length = 128, encoding = "legacy" },
  { opcode = "VEX.128.66.0F38.WIG 00 /r", form = "VPSHUFB xmm1, xmm2, xmm3/m128", op_en = "RVM", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F38.WIG 00 /r", form = "VPSHUFB ymm1, ymm2, ymm3/m256", op_en = "RVM", feature = "AVX2", vector_length = 256, encoding = "vex" },
  { opcode = "EVEX.128.66.0F38.WIG 00 /r", form = "VPSHUFB xmm1{k}{z}, xmm2, xmm3/m128", op_en = "RVM", feature = "AVX512BW+AVX512VL", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F38.WIG 00 /r", form = "VPSHUFB ymm1{k}{z}, ymm2, ymm3/m256", op_en = "RVM", feature = "AVX512BW+AVX512VL", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F38.WIG 00 /r", form = "VPSHUFB zmm1{k}{z}, zmm2, zmm3/m512", op_en = "RVM", feature = "AVX512BW", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  RM = ["ModRM:reg (r,w)", "ModRM:r/m (r)"],
  RVM = ["ModRM:reg (r,w)", "VEX.vvvv (r)", "ModRM:r/m (r)"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
Shuffles bytes in the first source operand using shuffle control mask from the second source operand. For each byte position i, if the most significant bit of the corresponding control byte is set, the destination byte is zeroed. Otherwise, the low 4 bits of the control byte select the source byte position from the first source operand (within the same 128-bit lane for 256/512-bit versions).
"""

handler = "x86_pshufb"
jit_lowering = "arm64_pshufb"
fallback = "zig_pshufb"

neon_register_model = "x86 SIMD registers mapped to ARM64 SIMD registers."
neon_flag_model = "No x86 flags affected."
neon_assembly = "// ARM64 NEON: TBL/TBX"
neon_notes = ["The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
