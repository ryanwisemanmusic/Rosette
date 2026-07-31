// ADD/HADDPS.inc
// ARM64/NEON translation mirror generated from ISA/x86/ADD/HADDPS.inc.
// Source contract: HADDPS — Packed Single Precision Floating-Point Horizontal Add.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
HADDPS: horizontal add of adjacent single-precision pairs within each source.
Category: simd_float_horizontal_add.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ADD/HADDPS.inc"
x86_handler = "x86_haddps"
neon_lowering = "arm64_haddps_simd"
lowering_kind = "arm64_scalar"

name = "HADDPS"
category = "simd_float_horizontal_add"
feature = "SSE3"
element_type = "f32"
legacy_width = 128
lanes_128 = 4
lanes_256 = 8

encodings = [
  { opcode = "F2 0F 7C /r", form = "HADDPS xmm1, xmm2/m128", op_en = "RM", feature = "SSE3" },
  { opcode = "VEX.128.F2.0F.WIG 7C /r", form = "VHADDPS xmm1, xmm2, xmm3/m128", op_en = "RVM", feature = "AVX" },
  { opcode = "VEX.256.F2.0F.WIG 7C /r", form = "VHADDPS ymm1, ymm2, ymm3/m256", op_en = "RVM", feature = "AVX" }
]

operand_encodings = [
  { op_en = "RM", tuple = "N/A", operand1 = "ModRM:reg (r,w)", operand2 = "ModRM:r/m (r)", operand3 = "N/A", operand4 = "N/A" },
  { op_en = "RVM", tuple = "N/A", operand1 = "ModRM:reg (w)", operand2 = "VEX.vvvv (r)", operand3 = "ModRM:r/m (r)", operand4 = "N/A" }
]

semantic_legacy = """
DEST[31:0] = SRC1[63:32] + SRC1[31:0];
DEST[63:32] = SRC1[127:96] + SRC1[95:64];
DEST[95:64] = SRC2[31:0] + SRC2[63:32];
DEST[127:96] = SRC2[127:96] + SRC2[95:64];
DEST[MAXVL-1:128] unchanged;
"""

semantic_vex_128 = """
DEST[31:0] = SRC1[63:32] + SRC1[31:0];
DEST[63:32] = SRC1[127:96] + SRC1[95:64];
DEST[95:64] = SRC2[31:0] + SRC2[63:32];
DEST[127:96] = SRC2[127:96] + SRC2[95:64];
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
DEST[31:0] = SRC1[63:32] + SRC1[31:0];
DEST[63:32] = SRC1[127:96] + SRC1[95:64];
DEST[95:64] = SRC2[31:0] + SRC2[63:32];
DEST[127:96] = SRC2[127:96] + SRC2[95:64];
DEST[159:128] = SRC1[191:160] + SRC1[159:128];
DEST[191:160] = SRC1[255:224] + SRC1[223:192];
DEST[223:192] = SRC2[31:0] + SRC2[63:32];
DEST[255:224] = SRC2[127:96] + SRC2[95:64];
"""

flags_written = []

handler = "x86_haddps"
jit_lowering = "arm64_haddps_simd"

neon_register_model = """
x86 XMM/YMM registers mapped to ARM64 Vn registers.
"""

neon_flag_model = """
No x86 flags modified by HADDPS.
"""

neon_assembly = """
// NEON lowering: use ext + fadd for horizontal pair addition
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
