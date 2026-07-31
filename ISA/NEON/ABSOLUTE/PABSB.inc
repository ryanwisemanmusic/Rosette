// ABSOLUTE/PABSB.inc
// ARM64/NEON translation mirror.
// Source contract: PABSB — Packed Absolute Value (Byte).

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ABSOLUTE/PABSB.inc"
neon_lowering = "arm64_abs_simd"
lowering_kind = "neon_vector"

name = "PABSB"
category = "simd_integer_absolute"
feature = "SSSE3"
element_type = "i8"
legacy_width = 128
lanes_128 = 16
lanes_256 = 32
lanes_512 = 64

encodings = [
  { opcode = "NP 0F 38 1C /r", form = "PABSB mm1, mm2/m64", op_en = "A", feature = "SSSE3" },
  { opcode = "66 0F 38 1C /r", form = "PABSB xmm1, xmm2/m128", op_en = "A", feature = "SSSE3" },
  { opcode = "VEX.128.66.0F38.WIG 1C /r", form = "VPABSB xmm1, xmm2/m128", op_en = "A", feature = "AVX" },
  { opcode = "VEX.256.66.0F38.WIG 1C /r", form = "VPABSB ymm1, ymm2/m256", op_en = "A", feature = "AVX2" },
  { opcode = "EVEX.128.66.0F38.WIG 1C /r", form = "VPABSB xmm1 {k1}{z}, xmm2/m128", op_en = "B", feature = "AVX512VL+AVX512BW" },
  { opcode = "EVEX.256.66.0F38.WIG 1C /r", form = "VPABSB ymm1 {k1}{z}, ymm2/m256", op_en = "B", feature = "AVX512VL+AVX512BW" },
  { opcode = "EVEX.512.66.0F38.WIG 1C /r", form = "VPABSB zmm1 {k1}{z}, zmm2/m512", op_en = "B", feature = "AVX512BW" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "ModRM:reg (w)", operand2 = "ModRM:r/m (r)", operand3 = "N/A", operand4 = "N/A" },
  { op_en = "B", tuple = "Full Mem", operand1 = "ModRM:reg (w)", operand2 = "ModRM:r/m (r)", operand3 = "N/A", operand4 = "N/A" }
]

semantic = """
PABSB: compute absolute value of each signed byte element, storing unsigned result.
Category: simd_integer_absolute.
"""

semantic_legacy = """
for lane in 0..lanes:
    DEST.u8[lane] = abs(SRC.i8[lane]);
DEST[MAXVL-1:128] unchanged;
"""

semantic_vex_128 = """
for lane in 0..16:
    DEST.u8[lane] = abs(SRC.i8[lane]);
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
for lane in 0..32:
    DEST.u8[lane] = abs(SRC.i8[lane]);
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
(KL, VL) = (16, 128), (32, 256), (64, 512)
for j in 0..KL:
    if k1[j] or no_writemask:
        DEST.u8[j*8+7:j*8] = abs(SRC.i8[j*8+7:j*8]);
    else if merging:
        DEST.u8[j*8+7:j*8] unchanged;
    else:
        DEST.u8[j*8+7:j*8] = 0;
DEST[MAXVL-1:VL] = 0;
"""

flags_written = []

handler = "x86_pabsb"
jit_lowering = "arm64_abs_simd"

neon_register_model = """
x86 XMM/YMM/ZMM registers mapped to ARM64 Vn registers. PABSB/VPABSB is a lane-wise SIMD absolute value.
"""

neon_flag_model = """
No x86 flags modified by PABSB.
"""

neon_assembly = """
abs Vd.16B, Vn.16B
// 128-bit: abs Vd.16B, Vn.16B
// 256-bit: abs Vd.16B, Vn.16B (low) + abs Vd2.16B, Vn2.16B (high)
// 512-bit: abs Vd.16B, Vn.16B (4 lanes)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
