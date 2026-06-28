// SQRTSD.inc

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
SQRTSD: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_floating_point.
"""

name = "SQRTSD"
category = "simd_floating_point"
feature = "SSE2"
element_type = "f64"

encodings = [
  { opcode = "F2 0F 51 /r", form = "SQRTSD xmm1, xmm2/m64", op_en = "A", feature = "SSE2" },
  { opcode = "VEX.LIG.F2.0F.WIG 51 /r", form = "VSQRTSD xmm1, xmm2, xmm3/m64", op_en = "B", feature = "AVX" },
  { opcode = "EVEX.LLIG.F2.0F.W1 51 /r", form = "VSQRTSD xmm1{k1}{z}, xmm2, xmm3/m64{er}", op_en = "C", feature = "AVX512F" }
]

element_size = 64
lane_type = "scalar_double_precision_float"

mxcsr_used = true

simd_fp_exceptions = [
  "overflow",
  "underflow",
  "invalid",
  "precision",
  "denormal"
]

flags_written = []

semantic_legacy_128 = """
DEST.f64[0] = sqrt(DEST.f64[0]);
DEST[MAXVL-1:64] unchanged;
"""

semantic_vex_128 = """
DEST.f64[0] = sqrt(SRC2.f64[0]);
DEST.f64[1] = SRC1.f64[1];
DEST[MAXVL-1:128] = 0;
"""

semantic_evex = """
if k1[0] or no writemask:
    DEST.f64[0] = sqrt(SRC2.f64[0]);
else if zero_masking:
    DEST.f64[0] = 0;
DEST.f64[1] = SRC1.f64[1];
DEST[MAXVL-1:128] = 0;
"""

handler = "x86_sqrtsd"
jit_lowering = "arm64_scalar_fsqrt_d"
