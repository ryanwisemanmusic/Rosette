// CONCATENATE/VPSHLDD.inc
// ARM64/NEON translation mirror generated from ISA/x86/CONCATENATE/VPSHLDD.inc.
// Source contract: VPSHLDD — Concatenate and Shift Left Packed Data Logical.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "see preserved_source_contract", operand_4 = "N/A" },
]
semantic = """
VPSHLDD: concatenate packed dword data, extract shifted left result.
Category: simd_integer_concatenate_shift.
"""

name = "VPSHLDD"
category = "simd_integer_concatenate_shift"
feature = "AVX512_VBMI2"
element_type = "u32"
legacy_width = 0
lanes_128 = 4
lanes_256 = 8
lanes_512 = 16

encodings = [
  { opcode = "EVEX.128.66.0F3A.W0 71 /r /ib", form = "VPSHLDD xmm1{k1}{z}, xmm2, xmm3/m128/m32bcst", op_en = "B", feature = "AVX512_VBMI2+AVX512VL", imm = 8 },
  { opcode = "EVEX.256.66.0F3A.W0 71 /r /ib", form = "VPSHLDD ymm1{k1}{z}, ymm2, ymm3/m256/m32bcst", op_en = "B", feature = "AVX512_VBMI2+AVX512VL", imm = 8 },
  { opcode = "EVEX.512.66.0F3A.W0 71 /r /ib", form = "VPSHLDD zmm1{k1}{z}, zmm2, zmm3/m512/m32bcst", op_en = "B", feature = "AVX512_VBMI2", imm = 8 }
]

operand_encodings = [
  { op_en = "A", tuple = "Full Mem", operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "imm8" },
  { op_en = "B", tuple = "Full", operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "imm8" }
]

semantic_evex = """
(KL, VL) = (4, 128), (8, 256), (16, 512)
for j in 0..KL:
    if k1[j] or no_writemask:
        tsrc3 = (SRC3 is broadcast) ? SRC3.dword[0] : SRC3.dword[j];
        tmp = concat(SRC2.dword[j], tsrc3) << (imm8 & 31);
        DEST.dword[j] = tmp.dword[1];
    else if merging:
        u32[j] unchanged;
    else:
        u32[j] = 0;
DEST[MAXVL-1:VL] = 0;
"""

handler = "x86_vpshldd"
jit_lowering = "arm64_vpshldd"

neon_register_model = """
x86 ZMM/YMM/XMM registers mapped to ARM64 Vn registers with writemask support.
"""

neon_flag_model = """
No x86 flags modified by VPSHLDD.
"""

neon_assembly = """
// NEON lowering: concatenate + shift left operation for VPSHLDD
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
