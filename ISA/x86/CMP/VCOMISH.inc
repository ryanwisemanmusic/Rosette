// CMP/VCOMISH.inc
// Compare Scalar Ordered FP16 Values and Set EFLAGS.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VCOMISH: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_float_compare (scalar, sets EFLAGS).
"""

name = "VCOMISH"
category = "compare"
feature = "AVX512-FP16"
element_type = "f16"
scalar = true

encodings = [
  { opcode = "EVEX.LLIG.NP.MAP5.W0 2F /r", form = "VCOMISH xmm1, xmm2/m16{sae}", op_en = "A", feature = "AVX512-FP16", vector_length = 0, encoding = "evex" }
]

operand_encodings = [
  { op_en = "A", tuple = "Tuple1 Scalar", operand1 = "ModRM:reg (r, w)", operand2 = "ModRM:r/m (r)", operand3 = "N/A", operand4 = "N/A" }
]

flags_written = ["ZF", "PF", "CF", "OF=0", "SF=0", "AF=0"]
simd_fp_exceptions = ["Invalid", "Denormal"]

semantic_evex_scalar = """
Compares the FP16 value in the low word of xmm1 with the FP16 value in xmm2/m16.
Sets ZF, PF, CF according to the result (unordered/greater/less/equal). Clears OF, SF, AF.
Differs from VUCOMISH: signals #I on both SNaN and QNaN.
Result condition:
    xmm1 > xmm2:  ZF=0, PF=0, CF=0
    xmm1 < xmm2:  ZF=0, PF=0, CF=1
    xmm1 = xmm2:  ZF=1, PF=0, CF=0
    unordered:     ZF=1, PF=1, CF=1
DEST.f16[0] = SRC1.f16[0];  // destination register retains SRC1 value
DEST[MAXVL-1:16] = SRC1[MAXVL-1:16];
"""
