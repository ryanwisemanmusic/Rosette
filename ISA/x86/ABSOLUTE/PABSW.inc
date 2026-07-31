// ABSOLUTE/PABSW.inc
// ARM64/NEON translation mirror generated from ISA/x86/ABSOLUTE/PABSW.inc.
// Source contract: PABSW — Packed Absolute Value (Word).

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
PABSW: compute absolute value of each signed word element, storing unsigned result.
Category: simd_integer_absolute.
"""

name = "PABSW"
category = "simd_integer_absolute"
feature = "SSSE3"
element_type = "i16"
legacy_width = 128
lanes_128 = 8
lanes_256 = 16
lanes_512 = 32

encodings = [
  { opcode = "NP 0F 38 1D /r", form = "PABSW mm1, mm2/m64", op_en = "A", feature = "SSSE3" },
  { opcode = "66 0F 38 1D /r", form = "PABSW xmm1, xmm2/m128", op_en = "A", feature = "SSSE3" },
  { opcode = "VEX.128.66.0F38.WIG 1D /r", form = "VPABSW xmm1, xmm2/m128", op_en = "A", feature = "AVX" },
  { opcode = "VEX.256.66.0F38.WIG 1D /r", form = "VPABSW ymm1, ymm2/m256", op_en = "A", feature = "AVX2" },
  { opcode = "EVEX.128.66.0F38.WIG 1D /r", form = "VPABSW xmm1 {k1}{z}, xmm2/m128", op_en = "B", feature = "AVX512VL+AVX512BW" },
  { opcode = "EVEX.256.66.0F38.WIG 1D /r", form = "VPABSW ymm1 {k1}{z}, ymm2/m256", op_en = "B", feature = "AVX512VL+AVX512BW" },
  { opcode = "EVEX.512.66.0F38.WIG 1D /r", form = "VPABSW zmm1 {k1}{z}, zmm2/m512", op_en = "B", feature = "AVX512BW" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "ModRM:reg (w)", operand2 = "ModRM:r/m (r)", operand3 = "N/A", operand4 = "N/A" },
  { op_en = "B", tuple = "Full Mem", operand1 = "ModRM:reg (w)", operand2 = "ModRM:r/m (r)", operand3 = "N/A", operand4 = "N/A" }
]

semantic_legacy = """
for lane in 0..lanes:
    DEST.u16[lane] = abs(SRC.i16[lane]);
DEST[MAXVL-1:128] unchanged;
"""

semantic_vex_128 = """
for lane in 0..8:
    DEST.u16[lane] = abs(SRC.i16[lane]);
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
for lane in 0..16:
    DEST.u16[lane] = abs(SRC.i16[lane]);
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
(KL, VL) = (8, 128), (16, 256), (32, 512)
for j in 0..KL:
    if k1[j] or no_writemask:
        DEST.u16[j*16+15:j*16] = abs(SRC.i16[j*16+15:j*16]);
    else if merging:
        DEST.u16[j*16+15:j*16] unchanged;
    else:
        DEST.u16[j*16+15:j*16] = 0;
DEST[MAXVL-1:VL] = 0;
"""

flags_written = []

handler = "x86_pabsw"
jit_lowering = "arm64_abs_simd"

neon_register_model = """
x86 XMM/YMM/ZMM registers mapped to ARM64 Vn registers. PABSW/VPABSW is a lane-wise SIMD absolute value.
"""

neon_flag_model = """
No x86 flags modified by PABSW.
"""

neon_assembly = """
abs Vd.8H, Vn.8H
// 128-bit: abs Vd.8H, Vn.8H
// 256-bit: abs Vd.8H, Vn.8H (low) + abs Vd2.8H, Vn2.8H (high)
// 512-bit: abs Vd.8H, Vn.8H (4 lanes)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
