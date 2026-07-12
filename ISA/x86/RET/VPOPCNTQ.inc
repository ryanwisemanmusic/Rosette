// VPOPCNTQ.inc

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "N/A", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VPOPCNTQ: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_integer_popcount.
"""

name = "VPOPCNTQ"
category = "simd_integer_popcount"
feature = "AVX512-VPOPCNTDQ"
element_type = "u64"

encodings = [
  { opcode = "EVEX.128.66.0F38.W1 55 /r", form = "VPOPCNTQ xmm1{k1}{z}, xmm2/m128/m64bcst", op_en = "B", feature = "AVX512-VPOPCNTDQ AVX512VL" },
  { opcode = "EVEX.256.66.0F38.W1 55 /r", form = "VPOPCNTQ ymm1{k1}{z}, ymm2/m256/m64bcst", op_en = "B", feature = "AVX512-VPOPCNTDQ AVX512VL" },
  { opcode = "EVEX.512.66.0F38.W1 55 /r", form = "VPOPCNTQ zmm1{k1}{z}, zmm2/m512/m64bcst", op_en = "B", feature = "AVX512-VPOPCNTDQ" }
]

element_size = 64
lane_type = "unsigned_qword"

lanes = {
  xmm = 2,
  ymm = 4,
  zmm = 8
}

mxcsr_used = false

simd_fp_exceptions = []

flags_written = []

semantic_evex = """
for lane in VL/64:
    if writemask_enabled:
        DEST.u64[lane] = POPCOUNT(SRC.u64[lane]);
    else if zero_masking:
        DEST.u64[lane] = 0;
DEST[MAXVL-1:VL] = 0;
"""

handler = "x86_vpopcntq"
jit_lowering = "arm64_neon_cnt"
fallback = "zig_lane_loop"
