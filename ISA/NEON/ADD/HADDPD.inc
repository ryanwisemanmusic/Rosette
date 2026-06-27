// ADD/HADDPD.inc
// ARM64/NEON mirror generated from ISA/x86/ADD/HADDPD.inc.
// This file preserves the x86 source contract and supplies the ARM64 lowering contract.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ADD/HADDPD.inc"
x86_handler = "x86_haddpd"
neon_lowering = "arm64_hadd_simd"
lowering_kind = "arm64_documented_contract"

// ADD/HADDPD.inc
// ARM64/NEON translation mirror generated from ISA/x86/ADD/HADDPD.inc.
// Source contract: HADDPD — Packed Double Precision Floating-Point Horizontal Add.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
HADDPD: horizontal add of adjacent double-precision pairs within each source.
Category: simd_float_horizontal_add.
"""

name = "HADDPD"
category = "simd_float_horizontal_add"
feature = "SSE3"
element_type = "f64"
legacy_width = 128
lanes_128 = 2
lanes_256 = 4

encodings = [
  { opcode = "66 0F 7C /r", form = "HADDPD xmm1, xmm2/m128", op_en = "RM", feature = "SSE3" },
  { opcode = "VEX.128.66.0F.WIG 7C /r", form = "VHADDPD xmm1, xmm2, xmm3/m128", op_en = "RVM", feature = "AVX" },
  { opcode = "VEX.256.66.0F.WIG 7C /r", form = "VHADDPD ymm1, ymm2, ymm3/m256", op_en = "RVM", feature = "AVX" }
]

operand_encodings = [
  { op_en = "RM", tuple = "N/A", operand1 = "ModRM:reg (r,w)", operand2 = "ModRM:r/m (r)", operand3 = "N/A", operand4 = "N/A" },
  { op_en = "RVM", tuple = "N/A", operand1 = "ModRM:reg (w)", operand2 = "VEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "N/A" }
]

semantic_legacy = """
DEST[63:0] = SRC1[127:64] + SRC1[63:0];
DEST[127:64] = SRC2[127:64] + SRC2[63:0];
DEST[MAXVL-1:128] unchanged;
"""

semantic_vex_128 = """
DEST[63:0] = SRC1[127:64] + SRC1[63:0];
DEST[127:64] = SRC2[127:64] + SRC2[63:0];
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
DEST[63:0] = SRC1[127:64] + SRC1[63:0];
DEST[127:64] = SRC2[127:64] + SRC2[63:0];
DEST[191:128] = SRC1[255:192] + SRC1[191:128];
DEST[255:192] = SRC2[255:192] + SRC2[191:128];
"""
