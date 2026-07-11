// MUL/PMULLD.inc
// ARM64/NEON translation mirror generated from ISA/x86/MUL/PMULLD.inc.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
PMULLD: preserve the operation and form-specific semantic blocks.
Category: simd_int_mul_low.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "MUL/PMULLD.inc"
x86_handler = "x86_pmulld"
neon_lowering = "arm64_neon_mul_v4i32"
lowering_kind = "neon_vector"

name = "PMULLD"
category = "simd_int_mul_low"
feature = "SSE4.1"
element_type = "i32"

encodings = [
  { opcode = "66 0F 38 40 /r", form = "PMULLD xmm1, xmm2/m128", op_en = "A", feature = "SSE4.1" },
  { opcode = "VEX.128.66.0F38.W0 40 /r", form = "VPMULLD xmm1, xmm2, xmm3/m128", op_en = "B", feature = "AVX" },
  { opcode = "VEX.256.66.0F38.W0 40 /r", form = "VPMULLD ymm1, ymm2, ymm3/m256", op_en = "B", feature = "AVX2" },
  { opcode = "EVEX.128.66.0F38.W0 40 /r", form = "VPMULLD xmm1 {k1}{z}, xmm2, xmm3/m128", op_en = "C", feature = "AVX512F AVX512VL" },
  { opcode = "EVEX.256.66.0F38.W0 40 /r", form = "VPMULLD ymm1 {k1}{z}, ymm2, ymm3/m256", op_en = "C", feature = "AVX512F AVX512VL" },
  { opcode = "EVEX.512.66.0F38.W0 40 /r", form = "VPMULLD zmm1 {k1}{z}, zmm2, zmm3/m512", op_en = "C", feature = "AVX512F" },
]

element_size = 32
lane_type = "dword"

lanes = {
  xmm = 4,
  ymm = 8,
  zmm = 16
}

mxcsr_used = false

simd_fp_exceptions = []

flags_written = []

semantic_legacy_128 = """
DEST.i32[0] = DEST.i32[0] * SRC.i32[0];
DEST.i32[1] = DEST.i32[1] * SRC.i32[1];
DEST.i32[2] = DEST.i32[2] * SRC.i32[2];
DEST.i32[3] = DEST.i32[3] * SRC.i32[3];
DEST[MAXVL-1:128] unchanged;
"""

semantic_vex_128 = """
DEST.i32[0] = SRC1.i32[0] * SRC2.i32[0];
DEST.i32[1] = SRC1.i32[1] * SRC2.i32[1];
DEST.i32[2] = SRC1.i32[2] * SRC2.i32[2];
DEST.i32[3] = SRC1.i32[3] * SRC2.i32[3];
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
DEST.i32[0] = SRC1.i32[0] * SRC2.i32[0];
DEST.i32[1] = SRC1.i32[1] * SRC2.i32[1];
DEST.i32[2] = SRC1.i32[2] * SRC2.i32[2];
DEST.i32[3] = SRC1.i32[3] * SRC2.i32[3];
DEST.i32[4] = SRC1.i32[4] * SRC2.i32[4];
DEST.i32[5] = SRC1.i32[5] * SRC2.i32[5];
DEST.i32[6] = SRC1.i32[6] * SRC2.i32[6];
DEST.i32[7] = SRC1.i32[7] * SRC2.i32[7];
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
for lane in VL:
    if writemask_enabled:
        DEST[lane] = SRC1[lane] * SRC2[lane];
    else if zero_masking:
        DEST[lane] = 0;
DEST[MAXVL-1:VL] = 0;
"""

handler = "x86_pmulld"
jit_lowering = "arm64_neon_mul_v4i32"
fallback = "zig_lane_loop"

neon_register_model = """
x86 xmm/ymm lanes are mapped onto ARM64 v registers; lane width and MAXVL zero/merge rules are preserved by the lowering.
"""

neon_flag_model = """
No flags are written by PMULLD.
"""

neon_assembly = """
mul vD.4s, vN.4s, vM.4s
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
