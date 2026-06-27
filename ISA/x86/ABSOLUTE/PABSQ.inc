// ABSOLUTE/PABSQ.inc
// ARM64/NEON translation mirror generated from ISA/x86/ABSOLUTE/PABSQ.inc.
// Source contract: PABSQ — Packed Absolute Value (Qword).

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
PABSQ: compute absolute value of each signed qword element, storing unsigned result.
Category: simd_integer_absolute.
"""

name = "PABSQ"
category = "simd_integer_absolute"
feature = "AVX512F"
element_type = "i64"
legacy_width = 128
lanes_128 = 2
lanes_256 = 4
lanes_512 = 8

encodings = [
  { opcode = "EVEX.128.66.0F38.W1 1F /r", form = "VPABSQ xmm1 {k1}{z}, xmm2/m128/m64bcst", op_en = "B", feature = "AVX512VL+AVX512F" },
  { opcode = "EVEX.256.66.0F38.W1 1F /r", form = "VPABSQ ymm1 {k1}{z}, ymm2/m256/m64bcst", op_en = "B", feature = "AVX512VL+AVX512F" },
  { opcode = "EVEX.512.66.0F38.W1 1F /r", form = "VPABSQ zmm1 {k1}{z}, zmm2/m512/m64bcst", op_en = "B", feature = "AVX512F" }
]

operand_encodings = [
  { op_en = "B", tuple = "Full Mem", operand1 = "ModRM:reg (w)", operand2 = "ModRM:r/m (r)", operand3 = "N/A", operand4 = "N/A" }
]

semantic_evex = """
(KL, VL) = (2, 128), (4, 256), (8, 512)
for j in 0..KL:
    if k1[j] or no_writemask:
        DEST.u64[j*64+63:j*64] = abs(SRC.i64[j*64+63:j*64]);
    else if merging:
        DEST.u64[j*64+63:j*64] unchanged;
    else:
        DEST.u64[j*64+63:j*64] = 0;
DEST[MAXVL-1:VL] = 0;
"""

handler = "x86_pabsq"
jit_lowering = "arm64_abs_simd"

neon_register_model = """
x86 XMM/YMM/ZMM registers mapped to ARM64 Vn registers. VPABSQ is a lane-wise SIMD absolute value.
"""

neon_flag_model = """
No x86 flags modified by VPABSQ.
"""

neon_assembly = """
abs Vd.2D, Vn.2D
// 128-bit: abs Vd.2D, Vn.2D
// 256-bit: abs Vd.2D, Vn.2D (low) + abs Vd2.2D, Vn2.2D (high)
// 512-bit: abs Vd.2D, Vn.2D (4 lanes)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
