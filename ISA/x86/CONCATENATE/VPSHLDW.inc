// CONCATENATE/VPSHLDW.inc
// ARM64/NEON translation mirror generated from ISA/x86/CONCATENATE/VPSHLDW.inc.
// Source contract: VPSHLDW — Concatenate and Shift Left Packed Data Logical.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "see preserved_source_contract", operand_4 = "N/A" },
]
semantic = """
VPSHLDW: concatenate packed word data, extract shifted left result.
Category: simd_integer_concatenate_shift.
"""

name = "VPSHLDW"
category = "simd_integer_concatenate_shift"
feature = "AVX512_VBMI2"
element_type = "u16"
legacy_width = 0
lanes_128 = 8
lanes_256 = 16
lanes_512 = 32

encodings = [
  { opcode = "EVEX.128.66.0F3A.W1 70 /r /ib", form = "VPSHLDW xmm1{k1}{z}, xmm2, xmm3/m128", op_en = "A", feature = "AVX512_VBMI2+AVX512VL", imm = 8 },
  { opcode = "EVEX.256.66.0F3A.W1 70 /r /ib", form = "VPSHLDW ymm1{k1}{z}, ymm2, ymm3/m256", op_en = "A", feature = "AVX512_VBMI2+AVX512VL", imm = 8 },
  { opcode = "EVEX.512.66.0F3A.W1 70 /r /ib", form = "VPSHLDW zmm1{k1}{z}, zmm2, zmm3/m512", op_en = "A", feature = "AVX512_VBMI2", imm = 8 }
]

operand_encodings = [
  { op_en = "A", tuple = "Full Mem", operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "imm8" },
  { op_en = "B", tuple = "Full", operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "imm8" }
]

semantic_evex = """
(KL, VL) = (8, 128), (16, 256), (32, 512)
for j in 0..KL:
    if k1[j] or no_writemask:
        tmp = concat(SRC2.word[j], SRC3.word[j]) << (imm8 & 15);
        DEST.word[j] = tmp.word[1];
    else if merging:
        u16[j] unchanged;
    else:
        u16[j] = 0;
DEST[MAXVL-1:VL] = 0;
"""

handler = "x86_vpshldw"
jit_lowering = "arm64_vpshldw"

neon_register_model = """
x86 ZMM/YMM/XMM registers mapped to ARM64 Vn registers with writemask support.
"""

neon_flag_model = """
No x86 flags modified by VPSHLDW.
"""

neon_assembly = """
// NEON lowering: concatenate + shift left operation for VPSHLDW
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
