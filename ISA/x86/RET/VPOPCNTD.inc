// VPOPCNTD.inc

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "N/A", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VPOPCNTD: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_integer_popcount.
"""

name = "VPOPCNTD"
category = "simd_integer_popcount"
feature = "AVX512-VPOPCNTDQ"
element_type = "u32"

encodings = [
  { opcode = "EVEX.128.66.0F38.W0 55 /r", form = "VPOPCNTD xmm1{k1}{z}, xmm2/m128/m32bcst", op_en = "B", feature = "AVX512-VPOPCNTDQ AVX512VL" },
  { opcode = "EVEX.256.66.0F38.W0 55 /r", form = "VPOPCNTD ymm1{k1}{z}, ymm2/m256/m32bcst", op_en = "B", feature = "AVX512-VPOPCNTDQ AVX512VL" },
  { opcode = "EVEX.512.66.0F38.W0 55 /r", form = "VPOPCNTD zmm1{k1}{z}, zmm2/m512/m32bcst", op_en = "B", feature = "AVX512-VPOPCNTDQ" }
]

element_size = 32
lane_type = "unsigned_dword"

lanes = {
  xmm = 4,
  ymm = 8,
  zmm = 16
}

mxcsr_used = false

simd_fp_exceptions = []

flags_written = []

semantic_evex = """
for lane in VL/32:
    if writemask_enabled:
        DEST.u32[lane] = POPCOUNT(SRC.u32[lane]);
    else if zero_masking:
        DEST.u32[lane] = 0;
DEST[MAXVL-1:VL] = 0;
"""

handler = "x86_vpopcntd"
jit_lowering = "arm64_neon_cnt"
fallback = "zig_lane_loop"
