// KUNPCKDQ.inc
// Unpack (interleave) mask register doublewords to quadwords.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
KUNPCKDQ: unpack 32-bit mask elements from source k2 and k3 into 64-bit elements in k1.
Category: mask_unpack.
"""

name = "KUNPCKDQ"
category = "mask_unpack"
feature = "AVX512BW"
element_type = "u32"

encodings = [
  { opcode = "VEX.L1.0F.W1 4B /r", form = "KUNPCKDQ k1, k2, k3", op_en = "RVR", feature = "AVX512BW", mode = "V/V", handler = "x86_kunpckdq" }
]

operand_encodings = [
  { op_en = "RVR", tuple = "N/A", operand1 = "ModRM:reg (w)", operand2 = "VEX.1vvv (r)", operand3 = "ModRM:r/m (r, ModRM:[7:6] must be 11b)", operand4 = "N/A" }
]

semantic_general = """
Interleave 32-bit mask elements from k2 and k3 into 64-bit elements in k1.
k1[31:0] = k2[31:0], k1[63:32] = k3[31:0], etc.
Upper bits of k1 zeroed.
"""

simd_fp_exceptions = []
other_exceptions = ["See Table 2-63, TYPE K20 (VEX-Encoded OpMask Instructions w/o Memory Arg)"]

handler = "x86_kunpckdq"
jit_lowering = "arm64_neon_zip"
