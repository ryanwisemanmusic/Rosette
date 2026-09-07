// ARITHMETIC/VPADDSB.inc
// ARM64/NEON mirror for signed saturating packed-byte addition.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ARITHMETIC/VPADDSB.inc"
x86_handler = "x86_vpaddsb"
neon_lowering = "arm64_sqadd_b"
lowering_kind = "neon_vector"

name = "VPADDSB"
aliases = []
category = "simd_integer_add_saturate"
feature = "AVX_AVX2_AVX512BW"
element_type = "i8"
element_size = 8

encodings = [
  { opcode = "VEX.128.66.0F EC /r", form = "VPADDSB xmm1, xmm2, xmm3/m128", op_en = "RVM", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F.WIG EC /r", form = "VPADDSB ymm1, ymm2, ymm3/m256", op_en = "RVM", feature = "AVX2", vector_length = 256, encoding = "vex" },
  { opcode = "EVEX.128.66.0F EC /r", form = "VPADDSB xmm1{k1}{z}, xmm2, xmm3/m128", op_en = "C", feature = "AVX512BW+AVX512VL", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F EC /r", form = "VPADDSB ymm1{k1}{z}, ymm2, ymm3/m256", op_en = "C", feature = "AVX512BW+AVX512VL", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F EC /r", form = "VPADDSB zmm1{k1}{z}, zmm2, zmm3/m512", op_en = "C", feature = "AVX512BW", vector_length = 512, encoding = "evex" }
]

operand_encoding = { ZO = [] }
simd_fp_exceptions = []
semantic_general = """
for each lane: DEST.i8 = signed_saturate(SRC1.i8 + SRC2.i8, 8).
VEX clears DEST[MAXVL-1:VL]; EVEX applies the writemask merge/zero rule.
"""
handler = "x86_vpaddsb"
jit_lowering = "arm64_sqadd_b"
fallback = "zig_vpaddsb"
neon_register_model = "XMM/YMM lanes map to NEON 8-bit lanes with the VEX/EVEX upper-bit rule preserved."
neon_flag_model = "VPADDSB does not modify x86 flags."
neon_assembly = "sqadd vD.16b, vN.16b, vM.16b"
neon_notes = ["The mirror retains the x86 saturation and masking contract."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
