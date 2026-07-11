// MUL/VPDPWSSD.inc
// ARM64/NEON translation mirror generated from ISA/x86/MUL/VPDPWSSD.inc.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
VPDPWSSD: preserve the operation and form-specific semantic blocks.
Category: simd_int_dot_product.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "MUL/VPDPWSSD.inc"
x86_handler = "x86_vpdpwssd"
neon_lowering = "arm64_neon_sdot"
lowering_kind = "neon_vector"

name = "VPDPWSSD"
category = "simd_int_dot_product"
feature = "AVX512VNNI"
element_type = "i16"

encodings = [
  { opcode = "VEX.128.66.0F38.W0 52 /r", form = "VPDPWSSD xmm1, xmm2, xmm3/m128", op_en = "B", feature = "VNNI" },
  { opcode = "VEX.256.66.0F38.W0 52 /r", form = "VPDPWSSD ymm1, ymm2, ymm3/m256", op_en = "B", feature = "VNNI" },
  { opcode = "EVEX.128.66.0F38.W0 52 /r", form = "VPDPWSSD xmm1 {k1}{z}, xmm2, xmm3/m128", op_en = "C", feature = "AVX512VNNI AVX512VL" },
  { opcode = "EVEX.256.66.0F38.W0 52 /r", form = "VPDPWSSD ymm1 {k1}{z}, ymm2, ymm3/m256", op_en = "C", feature = "AVX512VNNI AVX512VL" },
  { opcode = "EVEX.512.66.0F38.W0 52 /r", form = "VPDPWSSD zmm1 {k1}{z}, zmm2, zmm3/m512", op_en = "C", feature = "AVX512VNNI" },
]

element_size = 16
lane_type = "word"

lanes = {
  xmm = 8,
  ymm = 16,
  zmm = 32
}

mxcsr_used = false

simd_fp_exceptions = []

flags_written = []

semantic_legacy_128 = """
// No legacy SSE variant; VNNI only.
"""

semantic_vex_128 = """
DEST.i32[0] += (SRC1.i16[1]*SRC2.i16[1] + SRC1.i16[0]*SRC2.i16[0]);
DEST.i32[1] += (SRC1.i16[3]*SRC2.i16[3] + SRC1.i16[2]*SRC2.i16[2]);
DEST.i32[2] += (SRC1.i16[5]*SRC2.i16[5] + SRC1.i16[4]*SRC2.i16[4]);
DEST.i32[3] += (SRC1.i16[7]*SRC2.i16[7] + SRC1.i16[6]*SRC2.i16[6]);
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
DEST.i32[0] += (SRC1.i16[1]*SRC2.i16[1] + SRC1.i16[0]*SRC2.i16[0]);
DEST.i32[1] += (SRC1.i16[3]*SRC2.i16[3] + SRC1.i16[2]*SRC2.i16[2]);
// ... repeat for dwords 2-7 ...
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
(KL, VL) = (4, 128), (8, 256), (16, 512)
FOR j := 0 TO KL-1
    i := j * 16
    IF writemask_enabled:
        DEST.i32[j] += SRC1.i16[i+1:i] * SRC2.i16[i+1:i]
    ELSE if zero_masking:
        DEST.i32[j] = 0
DEST[MAXVL-1:VL] = 0
"""

handler = "x86_vpdpwssd"
jit_lowering = "arm64_neon_sdot"
fallback = "zig_lane_loop"

neon_register_model = """
x86 xmm/ymm lanes are mapped onto ARM64 v registers; lane width and MAXVL zero/merge rules are preserved by the lowering.
"""

neon_flag_model = """
No flags are written by VPDPWSSD.
"""

neon_assembly = """
sdot vD.4s, vN.8h, vM.8h
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
