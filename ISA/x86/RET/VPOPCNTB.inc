// VPOPCNTB.inc

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "N/A", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VPOPCNTB: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_integer_popcount.
"""

name = "VPOPCNTB"
category = "simd_integer_popcount"
feature = "AVX512-BITALG"
element_type = "u8"

encodings = [
  { opcode = "EVEX.128.66.0F38.W0 54 /r", form = "VPOPCNTB xmm1{k1}{z}, xmm2/m128", op_en = "A", feature = "AVX512-BITALG AVX512VL" },
  { opcode = "EVEX.256.66.0F38.W0 54 /r", form = "VPOPCNTB ymm1{k1}{z}, ymm2/m256", op_en = "A", feature = "AVX512-BITALG AVX512VL" },
  { opcode = "EVEX.512.66.0F38.W0 54 /r", form = "VPOPCNTB zmm1{k1}{z}, zmm2/m512", op_en = "A", feature = "AVX512-BITALG" }
]

element_size = 8
lane_type = "unsigned_byte"

lanes = {
  xmm = 16,
  ymm = 32,
  zmm = 64
}

mxcsr_used = false

simd_fp_exceptions = []

flags_written = []

semantic_evex = """
for lane in VL/8:
    if writemask_enabled:
        DEST.u8[lane] = POPCOUNT(SRC.u8[lane]);
    else if zero_masking:
        DEST.u8[lane] = 0;
DEST[MAXVL-1:VL] = 0;
"""

handler = "x86_vpopcntb"
jit_lowering = "arm64_neon_cnt"
fallback = "zig_lane_loop"
