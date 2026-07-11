// PHSUBD.inc
// Horizontal subtract packed doubleword integers.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
PHSUBD: horizontal subtract of adjacent 32-bit signed integer pairs within each source.
Category: simd_integer_horizontal_subtract.
"""

name = "PHSUBD"
category = "simd_integer_horizontal_subtract"
feature = "SSSE3"
element_type = "i32"
legacy_width = 64
lanes_128 = 4
lanes_256 = 8
mxcsr_used = false

encodings = [
  { opcode = "NP 0F 38 06 /r", form = "PHSUBD mm1, mm2/m64", op_en = "RM", feature = "SSSE3", mode = "V/V", handler = "x86_phsubd_mm_mmm64" },
  { opcode = "66 0F 38 06 /r", form = "PHSUBD xmm1, xmm2/m128", op_en = "RM", feature = "SSSE3", mode = "V/V", handler = "x86_phsubd_xmm_xmmm128" },
  { opcode = "VEX.128.66.0F38.WIG 06 /r", form = "VPHSUBD xmm1, xmm2, xmm3/m128", op_en = "RVM", feature = "AVX", mode = "V/V", handler = "x86_vphsubd_xmm_xmm_xmmm128" },
  { opcode = "VEX.256.66.0F38.WIG 06 /r", form = "VPHSUBD ymm1, ymm2, ymm3/m256", op_en = "RVM", feature = "AVX2", mode = "V/V", handler = "x86_vphsubd_ymm_ymm_ymmm256" }
]

operand_encodings = [
  { op_en = "RM", tuple = "N/A", operand1 = "ModRM:reg (r,w)", operand2 = "ModRM:r/m (r)", operand3 = "N/A", operand4 = "N/A" },
  { op_en = "RVM", tuple = "N/A", operand1 = "ModRM:reg (w)", operand2 = "VEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "N/A" }
]

simd_fp_exceptions = []
other_exceptions = ["Type 4 class exception conditions"]

handler = "x86_phsubd"
jit_lowering = "arm64_neon_hsub_d"
