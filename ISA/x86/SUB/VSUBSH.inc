// VSUBSH.inc
// Subtract scalar FP16 value (AVX512-FP16).

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VSUBSH: subtract the low FP16 element of the second source from the low FP16 element of the first source.
Category: simd_float_scalar_subtract.
"""

name = "VSUBSH"
category = "simd_float_scalar_subtract"
feature = "AVX512-FP16"
element_type = "f16"
legacy_width = 128
lanes_128 = 8
mxcsr_used = true

encodings = [
  { opcode = "EVEX.LLIG.F3.MAP5.W0 5C /r", form = "VSUBSH xmm1 {k1}{z}, xmm2, xmm3/m16{er}", op_en = "C", feature = "AVX512-FP16", tuple = "Tuple1 Scalar", handler = "x86_vsubsh_evex" }
]

operand_encodings = [
  { op_en = "C", tuple = "Tuple1 Scalar", operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "N/A" }
]

semantic_evex = """
if k1[0] or no writemask:
    DEST[15:0] = SRC1[15:0] - SRC2[15:0];
else merge old low element or zero according to masking mode;
DEST[127:16] = SRC1[127:16];
DEST[MAXVL-1:128] = 0;
"""

simd_fp_exceptions = ["overflow", "underflow", "invalid", "precision", "denormal"]
other_exceptions = ["EVEX Type E3 class exceptions"]

handler = "x86_vsubsh"
jit_lowering = "arm64_neon_fsub_sh"
