// PACK/PALIGNR.inc
source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "PACK/PALIGNR.inc"
x86_handler = "x86_palignr"
neon_lowering = "arm64_palignr"
lowering_kind = "arm64_documented_contract"

name = "PALIGNR"
aliases = []
category = "pack"
feature = "SSSE3"
element_type = "integer"
element_size = 0

encodings = [
  { opcode = "NP 0F 3A 0F /r ib", form = "PALIGNR mm1, mm2/m64, imm8", op_en = "RMI", feature = "SSSE3", vector_length = 0, encoding = "legacy" },
  { opcode = "66 0F 3A 0F /r ib", form = "PALIGNR xmm1, xmm2/m128, imm8", op_en = "RMI", feature = "SSSE3", vector_length = 128, encoding = "legacy" },
  { opcode = "VEX.128.66.0F3A.WIG 0F /r ib", form = "VPALIGNR xmm1, xmm2, xmm3/m128, imm8", op_en = "RVMI", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F3A.WIG 0F /r ib", form = "VPALIGNR ymm1, ymm2, ymm3/m256, imm8", op_en = "RVMI", feature = "AVX2", vector_length = 256, encoding = "vex" },
  { opcode = "EVEX.128.66.0F3A.WIG 0F /r ib", form = "VPALIGNR xmm1{k}{z}, xmm2, xmm3/m128, imm8", op_en = "RVMI", feature = "AVX512BW+AVX512VL", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F3A.WIG 0F /r ib", form = "VPALIGNR ymm1{k}{z}, ymm2, ymm3/m256, imm8", op_en = "RVMI", feature = "AVX512BW+AVX512VL", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F3A.WIG 0F /r ib", form = "VPALIGNR zmm1{k}{z}, zmm2, zmm3/m512, imm8", op_en = "RVMI", feature = "AVX512BW", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  RM = ["ModRM:reg (r,w)", "ModRM:r/m (r)"],
  RMI = ["ModRM:reg (r,w)", "ModRM:r/m (r)", "imm8"],
  RVMI = ["ModRM:reg (r,w)", "VEX.vvvv (r)", "ModRM:r/m (r)", "imm8"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
Concatenates the destination operand with the source operand to form an intermediate 2X-byte vector, then shifts this concatenated vector right by the byte count specified in imm8. The lower X bytes of the shifted result are written to the destination. For VEX/EVEX forms, the first source operand (from VEX.vvvv) provides the upper bytes and the second source provides the lower bytes of the concatenation.
"""

handler = "x86_palignr"
jit_lowering = "arm64_palignr"
fallback = "zig_palignr"

neon_register_model = "x86 SIMD registers mapped to ARM64 SIMD registers."
neon_flag_model = "No x86 flags affected."
neon_assembly = "// ARM64 NEON: EXT"
neon_notes = ["The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
