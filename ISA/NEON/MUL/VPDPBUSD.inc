// MUL/VPDPBUSD.inc
// ARM64/NEON translation mirror generated from ISA/x86/MUL/VPDPBUSD.inc.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VPDPBUSD: preserve the operation and form-specific semantic blocks.
Category: simd_int_dot_product.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "MUL/VPDPBUSD.inc"
x86_handler = "x86_vpdpbusd"
neon_lowering = "arm64_neon_udot"
lowering_kind = "neon_vector"

name = "VPDPBUSD"
category = "simd_int_dot_product"
feature = "AVX512VNNI"
element_type = "u8"

encodings = [
  { opcode = "VEX.128.66.0F38.W0 50 /r", form = "VPDPBUSD xmm1, xmm2, xmm3/m128", op_en = "B", feature = "VNNI" },
  { opcode = "VEX.256.66.0F38.W0 50 /r", form = "VPDPBUSD ymm1, ymm2, ymm3/m256", op_en = "B", feature = "VNNI" },
  { opcode = "EVEX.128.66.0F38.W0 50 /r", form = "VPDPBUSD xmm1 {k1}{z}, xmm2, xmm3/m128", op_en = "C", feature = "AVX512VNNI AVX512VL" },
  { opcode = "EVEX.256.66.0F38.W0 50 /r", form = "VPDPBUSD ymm1 {k1}{z}, ymm2, ymm3/m256", op_en = "C", feature = "AVX512VNNI AVX512VL" },
  { opcode = "EVEX.512.66.0F38.W0 50 /r", form = "VPDPBUSD zmm1 {k1}{z}, zmm2, zmm3/m512", op_en = "C", feature = "AVX512VNNI" },
]

element_size = 8
lane_type = "byte"

lanes = {
  xmm = 16,
  ymm = 32,
  zmm = 64
}

mxcsr_used = false

simd_fp_exceptions = []

flags_written = []

semantic_legacy_128 = """
// No legacy SSE variant; VNNI only.
"""

semantic_vex_128 = """
DEST.i32[0] += SRC1.u8[3]*SRC2.i8[3] + SRC1.u8[2]*SRC2.i8[2] + SRC1.u8[1]*SRC2.i8[1] + SRC1.u8[0]*SRC2.i8[0];
DEST.i32[1] += SRC1.u8[7]*SRC2.i8[7] + SRC1.u8[6]*SRC2.i8[6] + SRC1.u8[5]*SRC2.i8[5] + SRC1.u8[4]*SRC2.i8[4];
DEST.i32[2] += SRC1.u8[11]*SRC2.i8[11] + SRC1.u8[10]*SRC2.i8[10] + SRC1.u8[9]*SRC2.i8[9] + SRC1.u8[8]*SRC2.i8[8];
DEST.i32[3] += SRC1.u8[15]*SRC2.i8[15] + SRC1.u8[14]*SRC2.i8[14] + SRC1.u8[13]*SRC2.i8[13] + SRC1.u8[12]*SRC2.i8[12];
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
DEST.i32[0] += SRC1.u8[3]*SRC2.i8[3] + SRC1.u8[2]*SRC2.i8[2] + SRC1.u8[1]*SRC2.i8[1] + SRC1.u8[0]*SRC2.i8[0];
DEST.i32[1] += SRC1.u8[7]*SRC2.i8[7] + SRC1.u8[6]*SRC2.i8[6] + SRC1.u8[5]*SRC2.i8[5] + SRC1.u8[4]*SRC2.i8[4];
// ... repeat for dwords 2-7 ...
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
(KL, VL) = (4, 128), (8, 256), (16, 512)
FOR j := 0 TO KL-1
    i := j * 32
    IF writemask_enabled:
        DEST.i32[j] += SRC1.u8[i+31:i] * SRC2.i8[i+31:i]
    ELSE if zero_masking:
        DEST.i32[j] = 0
DEST[MAXVL-1:VL] = 0
"""

handler = "x86_vpdpbusd"
jit_lowering = "arm64_neon_udot"
fallback = "zig_lane_loop"

neon_register_model = """
x86 xmm/ymm lanes are mapped onto ARM64 v registers; lane width and MAXVL zero/merge rules are preserved by the lowering.
"""

neon_flag_model = """
No flags are written by VPDPBUSD.
"""

neon_assembly = """
udot vD.4s, vN.16b, vM.16b
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
