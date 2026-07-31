// ABSOLUTE/PABSD.inc
// ARM64/NEON translation mirror.
// Source contract: PABSD — Packed Absolute Value (Dword).

semantic = """
PABSD: compute absolute value of each signed dword element, storing unsigned result.
Category: simd_integer_absolute.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ABSOLUTE/PABSD.inc"
neon_lowering = "arm64_abs_simd"

name = "PABSD"
category = "simd_integer_absolute"
feature = "SSSE3"
element_type = "i32"
legacy_width = 128
lanes_128 = 4
lanes_256 = 8
lanes_512 = 16

encodings = [
  { opcode = "NP 0F 38 1E /r", form = "PABSD mm1, mm2/m64", op_en = "A", feature = "SSSE3" },
  { opcode = "66 0F 38 1E /r", form = "PABSD xmm1, xmm2/m128", op_en = "A", feature = "SSSE3" },
  { opcode = "VEX.128.66.0F38.WIG 1E /r", form = "VPABSD xmm1, xmm2/m128", op_en = "A", feature = "AVX" },
  { opcode = "VEX.256.66.0F38.WIG 1E /r", form = "VPABSD ymm1, ymm2/m256", op_en = "A", feature = "AVX2" },
  { opcode = "EVEX.128.66.0F38.W0 1E /r", form = "VPABSD xmm1 {k1}{z}, xmm2/m128/m32bcst", op_en = "B", feature = "AVX512VL+AVX512F" },
  { opcode = "EVEX.256.66.0F38.W0 1E /r", form = "VPABSD ymm1 {k1}{z}, ymm2/m256/m32bcst", op_en = "B", feature = "AVX512VL+AVX512F" },
  { opcode = "EVEX.512.66.0F38.W0 1E /r", form = "VPABSD zmm1 {k1}{z}, zmm2/m512/m32bcst", op_en = "B", feature = "AVX512F" }
]

operand_encodings = [
  { op_en = "A", tuple = "N/A", operand1 = "ModRM:reg (w)", operand2 = "ModRM:r/m (r)", operand3 = "N/A", operand4 = "N/A" },
  { op_en = "B", tuple = "Full Mem", operand1 = "ModRM:reg (w)", operand2 = "ModRM:r/m (r)", operand3 = "N/A", operand4 = "N/A" }
]

semantic_legacy = """
for lane in 0..lanes:
    DEST.u32[lane] = abs(SRC.i32[lane]);
DEST[MAXVL-1:128] unchanged;
"""

semantic_vex_128 = """
for lane in 0..4:
    DEST.u32[lane] = abs(SRC.i32[lane]);
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
for lane in 0..8:
    DEST.u32[lane] = abs(SRC.i32[lane]);
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
(KL, VL) = (4, 128), (8, 256), (16, 512)
for j in 0..KL:
    if k1[j] or no_writemask:
        DEST.u32[j*32+31:j*32] = abs(SRC.i32[j*32+31:j*32]);
    else if merging:
        DEST.u32[j*32+31:j*32] unchanged;
    else:
        DEST.u32[j*32+31:j*32] = 0;
DEST[MAXVL-1:VL] = 0;
"""

neon_register_model = """
x86 XMM/YMM/ZMM registers mapped to ARM64 Vn registers. PABSD/VPABSD is a lane-wise SIMD absolute value.
"""

neon_flag_model = """
No x86 flags modified by PABSD.
"""

neon_assembly = """
abs Vd.4S, Vn.4S
// 128-bit: abs Vd.4S, Vn.4S
// 256-bit: abs Vd.4S, Vn.4S (low) + abs Vd2.4S, Vn2.4S (high)
// 512-bit: abs Vd.4S, Vn.4S (4 lanes)
"""

flags_written = []
