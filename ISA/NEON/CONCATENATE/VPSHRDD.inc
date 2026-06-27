// CONCATENATE/VPSHRDD.inc
// ARM64/NEON mirror generated from ISA/x86/CONCATENATE/VPSHRDD.inc.
// This file preserves the x86 source contract and supplies the ARM64 lowering contract.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONCATENATE/VPSHRDD.inc"
x86_handler = "x86_vpshrdd"
neon_lowering = "arm64_vpshrdd"
lowering_kind = "arm64_documented_contract"

// CONCATENATE/VPSHRDD.inc
// ARM64/NEON translation mirror generated from ISA/x86/CONCATENATE/VPSHRDD.inc.
// Source contract: VPSHRDD — Concatenate and Shift Right Packed Data Logical.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "see preserved_source_contract", operand_4 = "N/A" },
]
semantic = """
VPSHRDD: concatenate packed dword data, extract shifted right result.
Category: simd_integer_concatenate_shift.
"""

name = "VPSHRDD"
category = "simd_integer_concatenate_shift"
feature = "AVX512_VBMI2"
element_type = "u32"
legacy_width = 0
lanes_128 = 4
lanes_256 = 8
lanes_512 = 16

encodings = [
  { opcode = "EVEX.128.66.0F3A.W0 73 /r /ib", form = "VPSHRDD xmm1{k1}{z}, xmm2, xmm3/m128/m32bcst", op_en = "B", feature = "AVX512_VBMI2+AVX512VL", imm = 8 },
  { opcode = "EVEX.256.66.0F3A.W0 73 /r /ib", form = "VPSHRDD ymm1{k1}{z}, ymm2, ymm3/m256/m32bcst", op_en = "B", feature = "AVX512_VBMI2+AVX512VL", imm = 8 },
  { opcode = "EVEX.512.66.0F3A.W0 73 /r /ib", form = "VPSHRDD zmm1{k1}{z}, zmm2, zmm3/m512/m32bcst", op_en = "B", feature = "AVX512_VBMI2", imm = 8 }
]

operand_encodings = [
  { op_en = "A", tuple = "Full Mem", operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "imm8" },
  { op_en = "B", tuple = "Full", operand1 = "ModRM:reg (w)", operand2 = "EVEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "imm8" }
]
