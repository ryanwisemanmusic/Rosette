// MUL/PMADDUBSW.inc
// ARM64/NEON translation mirror generated from ISA/x86/MUL/PMADDUBSW.inc.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
PMADDUBSW: preserve the operation and form-specific semantic blocks.
Category: simd_int_mul_add.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "MUL/PMADDUBSW.inc"
x86_handler = "x86_pmaddubsw"
neon_lowering = "arm64_neon_sdot_v8i8"
lowering_kind = "neon_vector"

name = "PMADDUBSW"
category = "simd_int_mul_add"
feature = "SSSE3"
element_type = "u8"

encodings = [
  { opcode = "NP 0F 38 04 /r", form = "PMADDUBSW mm1, mm2/m64", op_en = "A", feature = "SSSE3" },
  { opcode = "66 0F 38 04 /r", form = "PMADDUBSW xmm1, xmm2/m128", op_en = "A", feature = "SSSE3" },
  { opcode = "VEX.128.66.0F38.WIG 04 /r", form = "VPMADDUBSW xmm1, xmm2, xmm3/m128", op_en = "B", feature = "AVX" },
  { opcode = "VEX.256.66.0F38.WIG 04 /r", form = "VPMADDUBSW ymm1, ymm2, ymm3/m256", op_en = "B", feature = "AVX2" },
  { opcode = "EVEX.128.66.0F38.WIG 04 /r", form = "VPMADDUBSW xmm1 {k1}{z}, xmm2, xmm3/m128", op_en = "C", feature = "AVX512BW AVX512VL" },
  { opcode = "EVEX.256.66.0F38.WIG 04 /r", form = "VPMADDUBSW ymm1 {k1}{z}, ymm2, ymm3/m256", op_en = "C", feature = "AVX512BW AVX512VL" },
  { opcode = "EVEX.512.66.0F38.WIG 04 /r", form = "VPMADDUBSW zmm1 {k1}{z}, zmm2, zmm3/m512", op_en = "C", feature = "AVX512BW" },
]

element_size = 8
lane_type = "byte"

lanes = {
  mmx = 8,
  xmm = 16,
  ymm = 32,
  zmm = 64
}

mxcsr_used = false

simd_fp_exceptions = []

flags_written = []

semantic_legacy_128 = """
DEST.i16[0] = SaturateToSignedWord(SRC.u8[1]*DEST.u8[1] + SRC.u8[0]*DEST.u8[0]);
DEST.i16[1] = SaturateToSignedWord(SRC.u8[3]*DEST.u8[3] + SRC.u8[2]*DEST.u8[2]);
DEST.i16[2] = SaturateToSignedWord(SRC.u8[5]*DEST.u8[5] + SRC.u8[4]*DEST.u8[4]);
DEST.i16[3] = SaturateToSignedWord(SRC.u8[7]*DEST.u8[7] + SRC.u8[6]*DEST.u8[6]);
DEST.i16[4] = SaturateToSignedWord(SRC.u8[9]*DEST.u8[9] + SRC.u8[8]*DEST.u8[8]);
DEST.i16[5] = SaturateToSignedWord(SRC.u8[11]*DEST.u8[11] + SRC.u8[10]*DEST.u8[10]);
DEST.i16[6] = SaturateToSignedWord(SRC.u8[13]*DEST.u8[13] + SRC.u8[12]*DEST.u8[12]);
DEST.i16[7] = SaturateToSignedWord(SRC.u8[15]*DEST.u8[15] + SRC.u8[14]*DEST.u8[14]);
DEST[MAXVL-1:128] unchanged;
"""

semantic_vex_128 = """
DEST.i16[0] = SaturateToSignedWord(SRC2.u8[1]*SRC1.u8[1] + SRC2.u8[0]*SRC1.u8[0]);
DEST.i16[1] = SaturateToSignedWord(SRC2.u8[3]*SRC1.u8[3] + SRC2.u8[2]*SRC1.u8[2]);
DEST.i16[2] = SaturateToSignedWord(SRC2.u8[5]*SRC1.u8[5] + SRC2.u8[4]*SRC1.u8[4]);
DEST.i16[3] = SaturateToSignedWord(SRC2.u8[7]*SRC1.u8[7] + SRC2.u8[6]*SRC1.u8[6]);
DEST.i16[4] = SaturateToSignedWord(SRC2.u8[9]*SRC1.u8[9] + SRC2.u8[8]*SRC1.u8[8]);
DEST.i16[5] = SaturateToSignedWord(SRC2.u8[11]*SRC1.u8[11] + SRC2.u8[10]*SRC1.u8[10]);
DEST.i16[6] = SaturateToSignedWord(SRC2.u8[13]*SRC1.u8[13] + SRC2.u8[12]*SRC1.u8[12]);
DEST.i16[7] = SaturateToSignedWord(SRC2.u8[15]*SRC1.u8[15] + SRC2.u8[14]*SRC1.u8[14]);
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
DEST.i16[0] = SaturateToSignedWord(SRC2.u8[1]*SRC1.u8[1] + SRC2.u8[0]*SRC1.u8[0]);
DEST.i16[1] = SaturateToSignedWord(SRC2.u8[3]*SRC1.u8[3] + SRC2.u8[2]*SRC1.u8[2]);
// ... repeat for lanes 2-15 ...
DEST.i16[15] = SaturateToSignedWord(SRC2.u8[31]*SRC1.u8[31] + SRC2.u8[30]*SRC1.u8[30]);
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
(KL, VL) = (8, 128), (16, 256), (32, 512)
FOR j := 0 TO KL-1
    i := j * 16
    IF writemask_enabled:
        DEST.i16[j] := SaturateToSignedWord(SRC2.u8[i+7:i]*SRC1.u8[i+7:i] + SRC2.u8[i+15:i+8]*SRC1.u8[i+15:i+8])
    ELSE if zero_masking:
        DEST.i16[j] = 0
DEST[MAXVL-1:VL] = 0
"""

handler = "x86_pmaddubsw"
jit_lowering = "arm64_neon_sdot_v8i8"
fallback = "zig_lane_loop"

neon_register_model = """
x86 xmm/ymm lanes are mapped onto ARM64 v registers; lane width and MAXVL zero/merge rules are preserved by the lowering.
"""

neon_flag_model = """
No flags are written by PMADDUBSW.
"""

neon_assembly = """
sdot vD.4s, vN.16b, vM.16b
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
