// MAXSD.inc

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
MAXSD: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_float_scalar_max.
"""

name = "MAXSD"
category = "simd_float_scalar_max"
feature = "SSE2"
element_type = "f64"

encodings = [
  { opcode = "F2 0F 5F /r", form = "MAXSD xmm1, xmm2/m64", op_en = "A", feature = "SSE2" },
  { opcode = "VEX.LIG.F2.0F.WIG 5F /r", form = "VMAXSD xmm1, xmm2, xmm3/m64", op_en = "B", feature = "AVX" },
  { opcode = "EVEX.LLIG.F2.0F.W1 5F /r", form = "VMAXSD xmm1{k1}{z}, xmm2, xmm3/m64{er}", op_en = "C", feature = "AVX512F" }
]

element_size = 64
lane_type = "double_precision_float"

lanes = {
  xmm = 2,
  ymm = 0,
  zmm = 0
}

mxcsr_used = true

simd_fp_exceptions = [
  "invalid",
  "denormal"
]

flags_written = []

semantic_legacy_128 = """
DEST.f64[0] = MAX(DEST.f64[0], SRC.f64[0]);
DEST[MAXVL-1:64] unchanged;
"""

semantic_vex_128 = """
DEST.f64[0] = MAX(SRC1.f64[0], SRC2.f64[0]);
DEST[MAXVL-1:64] = 0;
"""

semantic_evex = """
IF k1[0] or *no writemask*:
    DEST.f64[0] = MAX(SRC1.f64[0], SRC2.f64[0]);
ELSE IF *zero-masking*:
    DEST.f64[0] = 0;
ELSE:
    *merge-masking*: DEST.f64[0] unchanged;
DEST[MAXVL-1:64] = 0;
"""

handler = "x86_maxsd"
jit_lowering = "arm64_neon_fmax_scalar"
fallback = "zig_lane_loop"
