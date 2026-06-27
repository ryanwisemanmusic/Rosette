// CONCATENATE/VPSHRDQ.inc
// ARM64/NEON mirror generated from ISA/x86/CONCATENATE/VPSHRDQ.inc.
// This file preserves the x86 source contract and supplies the ARM64 lowering contract.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONCATENATE/VPSHRDQ.inc"
x86_handler = "x86_vpshrdq"
neon_lowering = "arm64_vpshrdq"
lowering_kind = "arm64_documented_contract"

// CONCATENATE/VPSHRDQ.inc
// ARM64/NEON translation mirror generated from ISA/x86/CONCATENATE/VPSHRDQ.inc.
// Source contract: VPSHRDQ — Concatenate and Shift Right Packed Data Logical.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "see preserved_source_contract", operand_4 = "N/A" },
]
semantic = """
VPSHRDQ: concatenate packed qword data, extract shifted right result.
Category: simd_integer_concatenate_shift.
"""

name = "VPSHRDQ"
category = "simd_integer_concatenate_shift"
feature = "AVX512_VBMI2"
element_type = "u64"
legacy_width = 0
lanes_128 = 2
lanes_256 = 4
lanes_512 = 8

encodings = [
  { opcode = "EVEX.128.66.0F3A.W1 73 /r /ib", form = "VPSHRDQ xmm1{k1}{z}, xmm2, xmm3/m128/m64bcst", op_en = "B", feature = "AVX512_VBMI2+AVX512VL", imm = 8 },
  { opcode = "EVEX.256.66.0F3A.W1 73 /r /ib", form = "VPSHRDQ ymm1{k1}{z}, ymm2, ymm3/m256/m64bcst", op_en = "B", feature = "AVX512_VBMI2+AVX512VL", imm = 8 },
  { opcode = "EVEX.512.66.0F3A.W1 73 /r /ib", form = "VPSHRDQ zmm1{k1}{z}, zmm2, zmm3/m512/m64bcst", op_en = "B", feature = "AVX512_VBMI2", imm = 8 }
]

operand_encodings = [
  { op_en = "A", tuple = "Full Mem", operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "imm8" },
  { op_en = "B", tuple = "Full", operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "imm8" }
]
