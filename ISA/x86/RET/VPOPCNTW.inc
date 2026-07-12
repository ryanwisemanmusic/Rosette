// VPOPCNTW.inc

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "N/A", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VPOPCNTW: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_integer_popcount.
"""

name = "VPOPCNTW"
category = "simd_integer_popcount"
feature = "AVX512-BITALG"
element_type = "u16"

encodings = [
  { opcode = "EVEX.128.66.0F38.W1 54 /r", form = "VPOPCNTW xmm1{k1}{z}, xmm2/m128", op_en = "A", feature = "AVX512-BITALG AVX512VL" },
  { opcode = "EVEX.256.66.0F38.W1 54 /r", form = "VPOPCNTW ymm1{k1}{z}, ymm2/m256", op_en = "A", feature = "AVX512-BITALG AVX512VL" },
  { opcode = "EVEX.512.66.0F38.W1 54 /r", form = "VPOPCNTW zmm1{k1}{z}, zmm2/m512", op_en = "A", feature = "AVX512-BITALG" }
]

element_size = 16
lane_type = "unsigned_word"

lanes = {
  xmm = 8,
  ymm = 16,
  zmm = 32
}

mxcsr_used = false

simd_fp_exceptions = []

flags_written = []

semantic_evex = """
for lane in VL/16:
    if writemask_enabled:
        DEST.u16[lane] = POPCOUNT(SRC.u16[lane]);
    else if zero_masking:
        DEST.u16[lane] = 0;
DEST[MAXVL-1:VL] = 0;
"""

handler = "x86_vpopcntw"
jit_lowering = "arm64_neon_cnt"
fallback = "zig_lane_loop"
