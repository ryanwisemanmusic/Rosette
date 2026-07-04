// FULL_PERMUTE/VPERMI2D.inc
// VPERMI2D — Full Permute of Dwords From Two Tables Overwriting the Index.

name = "VPERMI2D"
category = "simd_permute"
feature = "AVX512F_AVX512VL"
element_type = "u32"
element_size = 32

encodings = [
  { opcode = "EVEX.128.66.0F38.W0 76 /r", form = "VPERMI2D xmm1 {k1}{z}, xmm2, xmm3/m128/m32bcst", op_en = "B", feature = "AVX512VL AVX512F", vector_length = 128, encoding = "evex", broadcast = "m32bcst" },
  { opcode = "EVEX.256.66.0F38.W0 76 /r", form = "VPERMI2D ymm1 {k1}{z}, ymm2, ymm3/m256/m32bcst", op_en = "B", feature = "AVX512VL AVX512F", vector_length = 256, encoding = "evex", broadcast = "m32bcst" },
  { opcode = "EVEX.512.66.0F38.W0 76 /r", form = "VPERMI2D zmm1 {k1}{z}, zmm2, zmm3/m512/m32bcst", op_en = "B", feature = "AVX512F", vector_length = 512, encoding = "evex", broadcast = "m32bcst" }
]

operand_encoding = {
  B = { operand1 = "ModRM:reg (r,w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "N/A" }
}

lanes = { xmm = 4, ymm = 8, zmm = 16 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "See Table 2-50, Type E4NF Class Exception Conditions."
]

semantic = """
(KL, VL) = (4, 128), (8, 256), (16, 512). For each dword: DEST[i+31:i] := SRC2[SRC1[i+31:i]+31:SRC1[i+31:i]] with writemask and broadcast support. Uses two tables from SRC2 (table) and SRC1 (index), overwriting SRC1.
"""

exceptions = ["See Table 2-50, Type E4NF Class Exception Conditions."]

handler = "x86_vpermi2d"
jit_lowering = "arm64_vpermi2d"

neon_register_model = "VPERMI2D is an AVX512F/VL SIMD permute instruction. No NEON register effect."
neon_flag_model = "None."
neon_assembly = "// NEON lowering: VPERMI2D stub"
neon_notes = ["VPERMI2D permutes dwords from two tables using index in SRC1.", "ARM64 lowering uses NEON TBL/TBX primitives."]
abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
