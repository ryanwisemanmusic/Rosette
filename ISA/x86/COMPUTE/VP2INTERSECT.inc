// VP2INTERSECT.inc

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VP2INTERSECT: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_int.
"""

name = "VP2INTERSECT"
aliases = ["VP2INTERSECTD", "VP2INTERSECTQ"]
category = "simd_int"
feature = "AVX512F"
element_type = "u32_u64"

encodings = [
  { opcode = "EVEX.NDS.128.F2.0F38.W0 68 /r", form = "VP2INTERSECTD k1+1, xmm2, xmm3/m128/m32bcst", op_en = "A", feature = "AVX512F", writes_mask = true },
  { opcode = "EVEX.NDS.256.F2.0F38.W0 68 /r", form = "VP2INTERSECTD k1+1, ymm2, ymm3/m256/m32bcst", op_en = "A", feature = "AVX512F", writes_mask = true },
  { opcode = "EVEX.NDS.512.F2.0F38.W0 68 /r", form = "VP2INTERSECTD k1+1, zmm2, zmm3/m512/m32bcst", op_en = "A", feature = "AVX512F", writes_mask = true },
  { opcode = "EVEX.NDS.128.F2.0F38.W1 68 /r", form = "VP2INTERSECTQ k1+1, xmm2, xmm3/m128/m64bcst", op_en = "A", feature = "AVX512F", writes_mask = true },
  { opcode = "EVEX.NDS.256.F2.0F38.W1 68 /r", form = "VP2INTERSECTQ k1+1, ymm2, ymm3/m256/m64bcst", op_en = "A", feature = "AVX512F", writes_mask = true },
  { opcode = "EVEX.NDS.512.F2.0F38.W1 68 /r", form = "VP2INTERSECTQ k1+1, zmm2, zmm3/m512/m64bcst", op_en = "A", feature = "AVX512F", writes_mask = true }
]

lanes = {
  xmm = 4,
  ymm = 8,
  zmm = 16
}

flags_written = []

semantic_avx512 = """
(KL, VL) = (4,128), (8,256), or (16,512) for DWORD;
(KL, VL) = (2,128), (4,256), or (8,512) for QWORD;
k1 = 0;
k2 = 0;
for j in 0..KL-1:
    i = j * element_size;
    if j > 0:
        for m in 0..j-1:
            if SRC1[i+31:i] == SRC1[m*32+31:m*32]:
                k1[j] = 1;
                k1[m] = 1;
            if SRC2[i+31:i] == SRC2[m*32+31:m*32]:
                k2[j] = 1;
                k2[m] = 1;
DEST = k1 (low 8/16 bits);
DEST_high = k2 (next 8/16 bits);
"""

handler = "x86_vp2intersect"
jit_lowering = "arm64_no_neon_equivalent"
