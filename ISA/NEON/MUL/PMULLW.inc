// MUL/PMULLW.inc
// ARM64/NEON translation mirror generated from ISA/x86/MUL/PMULLW.inc.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
PMULLW: preserve the operation and form-specific semantic blocks.
Category: simd_int_mul_low.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "MUL/PMULLW.inc"
x86_handler = "x86_pmullw"
neon_lowering = "arm64_neon_mul_v8i16"
lowering_kind = "neon_vector"

name = "PMULLW"
category = "simd_int_mul_low"
feature = "MMX"
element_type = "i16"

encodings = [
  { opcode = "NP 0F D5 /r", form = "PMULLW mm1, mm2/m64", op_en = "A", feature = "MMX" },
  { opcode = "66 0F D5 /r", form = "PMULLW xmm1, xmm2/m128", op_en = "A", feature = "SSE2" },
  { opcode = "VEX.128.66.0F.WIG D5 /r", form = "VPMULLW xmm1, xmm2, xmm3/m128", op_en = "B", feature = "AVX" },
  { opcode = "VEX.256.66.0F.WIG D5 /r", form = "VPMULLW ymm1, ymm2, ymm3/m256", op_en = "B", feature = "AVX2" },
  { opcode = "EVEX.128.66.0F.WIG D5 /r", form = "VPMULLW xmm1 {k1}{z}, xmm2, xmm3/m128", op_en = "C", feature = "AVX512BW AVX512VL" },
  { opcode = "EVEX.256.66.0F.WIG D5 /r", form = "VPMULLW ymm1 {k1}{z}, ymm2, ymm3/m256", op_en = "C", feature = "AVX512BW AVX512VL" },
  { opcode = "EVEX.512.66.0F.WIG D5 /r", form = "VPMULLW zmm1 {k1}{z}, zmm2, zmm3/m512", op_en = "C", feature = "AVX512BW" },
]

element_size = 16
lane_type = "word"

lanes = {
  mmx = 4,
  xmm = 8,
  ymm = 16,
  zmm = 32
}

mxcsr_used = false

simd_fp_exceptions = []

flags_written = []

semantic_legacy_128 = """
DEST.i16[0] = DEST.i16[0] * SRC.i16[0];
DEST.i16[1] = DEST.i16[1] * SRC.i16[1];
DEST.i16[2] = DEST.i16[2] * SRC.i16[2];
DEST.i16[3] = DEST.i16[3] * SRC.i16[3];
DEST.i16[4] = DEST.i16[4] * SRC.i16[4];
DEST.i16[5] = DEST.i16[5] * SRC.i16[5];
DEST.i16[6] = DEST.i16[6] * SRC.i16[6];
DEST.i16[7] = DEST.i16[7] * SRC.i16[7];
DEST[MAXVL-1:128] unchanged;
"""

semantic_vex_128 = """
DEST.i16[0] = SRC1.i16[0] * SRC2.i16[0];
DEST.i16[1] = SRC1.i16[1] * SRC2.i16[1];
DEST.i16[2] = SRC1.i16[2] * SRC2.i16[2];
DEST.i16[3] = SRC1.i16[3] * SRC2.i16[3];
DEST.i16[4] = SRC1.i16[4] * SRC2.i16[4];
DEST.i16[5] = SRC1.i16[5] * SRC2.i16[5];
DEST.i16[6] = SRC1.i16[6] * SRC2.i16[6];
DEST.i16[7] = SRC1.i16[7] * SRC2.i16[7];
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
DEST.i16[0] = SRC1.i16[0] * SRC2.i16[0];
DEST.i16[1] = SRC1.i16[1] * SRC2.i16[1];
// ... repeat for words 2-15 ...
DEST.i16[15] = SRC1.i16[15] * SRC2.i16[15];
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
(KL, VL) = (8, 128), (16, 256), (32, 512)
FOR j := 0 TO KL-1
    IF writemask_enabled:
        DEST.i16[j] := SRC1.i16[j] * SRC2.i16[j]
    ELSE if zero_masking:
        DEST.i16[j] = 0
DEST[MAXVL-1:VL] = 0
"""

handler = "x86_pmullw"
jit_lowering = "arm64_neon_mul_v8i16"
fallback = "zig_lane_loop"

neon_register_model = """
x86 xmm/ymm lanes are mapped onto ARM64 v registers; lane width and MAXVL zero/merge rules are preserved by the lowering.
"""

neon_flag_model = """
No flags are written by PMULLW.
"""

neon_assembly = """
mul vD.8h, vN.8h, vM.8h
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
