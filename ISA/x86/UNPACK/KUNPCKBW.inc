// KUNPCKBW.inc
// Unpack (interleave) mask register bytes to words.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
KUNPCKBW: unpack 8-bit mask elements from source k2 and k3 into 16-bit elements in k1.
Category: mask_unpack.
"""

name = "KUNPCKBW"
category = "mask_unpack"
feature = "AVX512F"
element_type = "u8"

encodings = [
  { opcode = "VEX.L1.66.0F.W0 4B /r", form = "KUNPCKBW k1, k2, k3", op_en = "RVR", feature = "AVX512F", mode = "V/V", handler = "x86_kunpckbw" }
]

operand_encodings = [
  { op_en = "RVR", tuple = "N/A", operand1 = "ModRM:reg (w)", operand2 = "VEX.1vvv (r)", operand3 = "ModRM:r/m (r, ModRM:[7:6] must be 11b)", operand4 = "N/A" }
]

semantic_general = """
Interleave 8-bit mask elements from k2 and k3 into 16-bit elements in k1.
k1[7:0] = k2[7:0], k1[15:8] = k3[7:0], etc.
Upper bits of k1 zeroed.
"""

simd_fp_exceptions = []
other_exceptions = ["See Table 2-63, TYPE K20 (VEX-Encoded OpMask Instructions w/o Memory Arg)"]

handler = "x86_kunpckbw"
jit_lowering = "arm64_neon_zip"
