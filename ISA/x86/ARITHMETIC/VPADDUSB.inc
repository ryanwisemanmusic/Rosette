// ARITHMETIC/VPADDUSB.inc
// Add packed unsigned bytes with unsigned saturation.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ARITHMETIC/VPADDUSB.inc"
x86_handler = "x86_vpaddusb"
neon_lowering = "arm64_uqadd_b"
lowering_kind = "neon_vector"

name = "VPADDUSB"
aliases = []
category = "simd_integer_add_saturate"
feature = "AVX_AVX2_AVX512BW"
element_type = "u8"
element_size = 8

encodings = [
  { opcode = "VEX.128.66.0F DC /r", form = "VPADDUSB xmm1, xmm2, xmm3/m128", op_en = "RVM", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F.WIG DC /r", form = "VPADDUSB ymm1, ymm2, ymm3/m256", op_en = "RVM", feature = "AVX2", vector_length = 256, encoding = "vex" },
  { opcode = "EVEX.128.66.0F DC /r", form = "VPADDUSB xmm1{k1}{z}, xmm2, xmm3/m128", op_en = "C", feature = "AVX512BW+AVX512VL", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F DC /r", form = "VPADDUSB ymm1{k1}{z}, ymm2, ymm3/m256", op_en = "C", feature = "AVX512BW+AVX512VL", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F DC /r", form = "VPADDUSB zmm1{k1}{z}, zmm2, zmm3/m512", op_en = "C", feature = "AVX512BW", vector_length = 512, encoding = "evex" }
]

operand_encoding = { ZO = [] }
simd_fp_exceptions = []
semantic_general = """
for each lane: DEST.u8 = unsigned_saturate(SRC1.u8 + SRC2.u8, 8).
VEX clears DEST[MAXVL-1:VL]; EVEX applies the writemask merge/zero rule.
"""
handler = "x86_vpaddusb"
jit_lowering = "arm64_uqadd_b"
fallback = "zig_vpaddusb"

neon_register_model = "VPADDUSB maps to 8-bit lanes in the corresponding NEON vector."
neon_flag_model = "VPADDUSB does not modify x86 flags."
neon_assembly = "uqadd vD.16b, vN.16b, vM.16b"
neon_notes = ["Unsigned saturation is architectural; modulo addition is not an equivalent lowering."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
