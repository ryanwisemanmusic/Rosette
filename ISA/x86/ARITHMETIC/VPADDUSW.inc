// ARITHMETIC/VPADDUSW.inc
// Add packed unsigned words with unsigned saturation.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ARITHMETIC/VPADDUSW.inc"
x86_handler = "x86_vpaddusw"
neon_lowering = "arm64_uqadd_w"
lowering_kind = "neon_vector"

name = "VPADDUSW"
aliases = []
category = "simd_integer_add_saturate"
feature = "AVX_AVX2_AVX512BW"
element_type = "u16"
element_size = 16

encodings = [
  { opcode = "VEX.128.66.0F DD /r", form = "VPADDUSW xmm1, xmm2, xmm3/m128", op_en = "RVM", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F.WIG DD /r", form = "VPADDUSW ymm1, ymm2, ymm3/m256", op_en = "RVM", feature = "AVX2", vector_length = 256, encoding = "vex" },
  { opcode = "EVEX.128.66.0F DD /r", form = "VPADDUSW xmm1{k1}{z}, xmm2, xmm3/m128", op_en = "C", feature = "AVX512BW+AVX512VL", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F DD /r", form = "VPADDUSW ymm1{k1}{z}, ymm2, ymm3/m256", op_en = "C", feature = "AVX512BW+AVX512VL", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F DD /r", form = "VPADDUSW zmm1{k1}{z}, zmm2, zmm3/m512", op_en = "C", feature = "AVX512BW", vector_length = 512, encoding = "evex" }
]

operand_encoding = { ZO = [] }
simd_fp_exceptions = []
semantic_general = """
for each lane: DEST.u16 = unsigned_saturate(SRC1.u16 + SRC2.u16, 16).
VEX clears DEST[MAXVL-1:VL]; EVEX applies the writemask merge/zero rule.
"""
handler = "x86_vpaddusw"
jit_lowering = "arm64_uqadd_w"
fallback = "zig_vpaddusw"

neon_register_model = "VPADDUSW maps to 16-bit lanes in the corresponding NEON vector."
neon_flag_model = "VPADDUSW does not modify x86 flags."
neon_assembly = "uqadd vD.8h, vN.8h, vM.8h"
neon_notes = ["Unsigned saturation is architectural; modulo addition is not an equivalent lowering."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
