// CONCATENATE/VPSHLDW.inc
// ARM64/NEON mirror generated from ISA/x86/CONCATENATE/VPSHLDW.inc.
// This file preserves the x86 source contract and supplies the ARM64 lowering contract.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONCATENATE/VPSHLDW.inc"
x86_handler = "x86_vpshldw"
neon_lowering = "arm64_vpshldw"
lowering_kind = "arm64_documented_contract"

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
