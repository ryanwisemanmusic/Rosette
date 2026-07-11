// VPMADD52LUQ.inc

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VPMADD52LUQ: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_int_mul_add_52.
"""

name = "VPMADD52LUQ"
category = "simd_int_mul_add_52"
feature = "AVX512_IFMA"
element_type = "u64"

encodings = [
  { opcode = "EVEX.128.66.0F38.W1 B4 /r", form = "VPMADD52LUQ xmm1{k1}{z}, xmm2, xmm3/m128/m64bcst", op_en = "A", feature = "AVX512_IFMA" },
  { opcode = "EVEX.256.66.0F38.W1 B4 /r", form = "VPMADD52LUQ ymm1{k1}{z}, ymm2, ymm3/m256/m64bcst", op_en = "A", feature = "AVX512_IFMA" },
  { opcode = "EVEX.512.66.0F38.W1 B4 /r", form = "VPMADD52LUQ zmm1{k1}{z}, zmm2, zmm3/m512/m64bcst", op_en = "A", feature = "AVX512_IFMA" }
]

element_size = 64
lane_type = "unsigned_quadword"

lanes = {
  xmm = 2,
  ymm = 4,
  zmm = 8
}

mxcsr_used = false

simd_fp_exceptions = []

flags_written = []

semantic_evex = """
for i in VL/64:
    if writemask_enabled:
        if broadcasting:
            tsrc2 = ZeroExtend64(SRC2.u64[0] & 0x000FFFFFFFFFFFFF);
        else:
            tsrc2 = ZeroExtend64(SRC2.u64[i] & 0x000FFFFFFFFFFFFF);
        temp104 = ZeroExtend64(SRC1.u64[i] & 0x000FFFFFFFFFFFFF) * tsrc2;
        DEST.u64[i] = DEST.u64[i] + ZeroExtend64(temp104[51:0]);
    else if zero_masking:
        DEST.u64[i] = 0;
DEST[MAXVL-1:VL] = 0;
"""

handler = "x86_vpmadd52luq"
jit_lowering = "arm64_neon_umull_52l"
fallback = "zig_lane_loop"
