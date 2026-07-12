// KUNPCKWD.inc
// Unpack (interleave) mask register words to doublewords.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
KUNPCKWD: unpack 16-bit mask elements from source k2 and k3 into 32-bit elements in k1.
Category: mask_unpack.
"""

name = "KUNPCKWD"
category = "mask_unpack"
feature = "AVX512BW"
element_type = "u16"

encodings = [
  { opcode = "VEX.L1.0F.W0 4B /r", form = "KUNPCKWD k1, k2, k3", op_en = "RVR", feature = "AVX512BW", mode = "V/V", handler = "x86_kunpckwd" }
]

operand_encodings = [
  { op_en = "RVR", tuple = "N/A", operand1 = "ModRM:reg (w)", operand2 = "VEX.1vvv (r)", operand3 = "ModRM:r/m (r, ModRM:[7:6] must be 11b)", operand4 = "N/A" }
]

semantic_general = """
Interleave 16-bit mask elements from k2 and k3 into 32-bit elements in k1.
k1[15:0] = k2[15:0], k1[31:16] = k3[15:0], etc.
Upper bits of k1 zeroed.
"""

simd_fp_exceptions = []
other_exceptions = ["See Table 2-63, TYPE K20 (VEX-Encoded OpMask Instructions w/o Memory Arg)"]

handler = "x86_kunpckwd"
jit_lowering = "arm64_neon_zip"
