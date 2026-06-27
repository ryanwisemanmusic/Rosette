// CONCATENATE/VPSHRDVQ.inc
// ARM64/NEON translation mirror generated from ISA/x86/CONCATENATE/VPSHRDVQ.inc.
// Source contract: VPSHRDVQ — Concatenate and Shift Right Packed Data Variable.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "see preserved_source_contract", operand_4 = "N/A" },
]
semantic = """
VPSHRDVQ: concatenate packed qword data, extract variable shifted right result.
Category: simd_integer_concatenate_shift.
"""

name = "VPSHRDVQ"
category = "simd_integer_concatenate_shift"
feature = "AVX512_VBMI2"
element_type = "u64"
legacy_width = 0
lanes_128 = 2
lanes_256 = 4
lanes_512 = 8

encodings = [
  { opcode = "EVEX.128.66.0F38.W1 73 /r", form = "VPSHRDVQ xmm1{k1}{z}, xmm2, xmm3/m128/m64bcst", op_en = "B", feature = "AVX512_VBMI2+AVX512VL" },
  { opcode = "EVEX.256.66.0F38.W1 73 /r", form = "VPSHRDVQ ymm1{k1}{z}, ymm2, ymm3/m256/m64bcst", op_en = "B", feature = "AVX512_VBMI2+AVX512VL" },
  { opcode = "EVEX.512.66.0F38.W1 73 /r", form = "VPSHRDVQ zmm1{k1}{z}, zmm2, zmm3/m512/m64bcst", op_en = "B", feature = "AVX512_VBMI2" }
]

operand_encodings = [
  { op_en = "A", tuple = "Full Mem", operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "imm8" },
  { op_en = "B", tuple = "Full", operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "imm8" }
]

semantic_evex = """
(KL, VL) = (2, 128), (4, 256), (8, 512)
for j in 0..KL:
    if k1[j] or no_writemask:
        tsrc3 = (SRC3 is broadcast) ? SRC3.qword[0] : SRC3.qword[j];
        DEST.qword[j] = concat(SRC2.qword[j], DEST.qword[j]) >> (tsrc3 & 63);
    else if merging:
        u64[j] unchanged;
    else:
        u64[j] = 0;
DEST[MAXVL-1:VL] = 0;
"""

handler = "x86_vpshrdvq"
jit_lowering = "arm64_vpshrdvq"

neon_register_model = """
x86 ZMM/YMM/XMM registers mapped to ARM64 Vn registers with writemask support.
"""

neon_flag_model = """
No x86 flags modified by VPSHRDVQ.
"""

neon_assembly = """
// NEON lowering: concatenate + variable shift right operation for VPSHRDVQ
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
