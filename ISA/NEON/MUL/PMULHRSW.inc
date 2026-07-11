// MUL/PMULHRSW.inc
// ARM64/NEON translation mirror generated from ISA/x86/MUL/PMULHRSW.inc.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
PMULHRSW: preserve the operation and form-specific semantic blocks.
Category: simd_int_mul_fixed.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "MUL/PMULHRSW.inc"
x86_handler = "x86_pmulhrsw"
neon_lowering = "arm64_neon_sqrdmulh"
lowering_kind = "neon_vector"

name = "PMULHRSW"
category = "simd_int_mul_fixed"
feature = "SSSE3"
element_type = "i16"

encodings = [
  { opcode = "NP 0F 38 0B /r", form = "PMULHRSW mm1, mm2/m64", op_en = "A", feature = "SSSE3" },
  { opcode = "66 0F 38 0B /r", form = "PMULHRSW xmm1, xmm2/m128", op_en = "A", feature = "SSSE3" },
  { opcode = "VEX.128.66.0F38.WIG 0B /r", form = "VPMULHRSW xmm1, xmm2, xmm3/m128", op_en = "B", feature = "AVX" },
  { opcode = "VEX.256.66.0F38.WIG 0B /r", form = "VPMULHRSW ymm1, ymm2, ymm3/m256", op_en = "B", feature = "AVX2" },
  { opcode = "EVEX.128.66.0F38.WIG 0B /r", form = "VPMULHRSW xmm1 {k1}{z}, xmm2, xmm3/m128", op_en = "C", feature = "AVX512BW AVX512VL" },
  { opcode = "EVEX.256.66.0F38.WIG 0B /r", form = "VPMULHRSW ymm1 {k1}{z}, ymm2, ymm3/m256", op_en = "C", feature = "AVX512BW AVX512VL" },
  { opcode = "EVEX.512.66.0F38.WIG 0B /r", form = "VPMULHRSW zmm1 {k1}{z}, zmm2, zmm3/m512", op_en = "C", feature = "AVX512BW" },
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
temp[31:0] = INT32(DEST.i16[0] * SRC.i16[0]) >> 14 + 1;
DEST.i16[0] = temp[16:1];
temp[31:0] = INT32(DEST.i16[1] * SRC.i16[1]) >> 14 + 1;
DEST.i16[1] = temp[16:1];
// ... repeat for words 2-7 ...
DEST[MAXVL-1:128] unchanged;
"""

semantic_vex_128 = """
temp[31:0] = INT32(SRC1.i16[0] * SRC2.i16[0]) >> 14 + 1;
DEST.i16[0] = temp[16:1];
temp[31:0] = INT32(SRC1.i16[1] * SRC2.i16[1]) >> 14 + 1;
DEST.i16[1] = temp[16:1];
// ... repeat for words 2-7 ...
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
temp[31:0] = INT32(SRC1.i16[0] * SRC2.i16[0]) >> 14 + 1;
DEST.i16[0] = temp[16:1];
// ... repeat for words 1-15 ...
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
(KL, VL) = (8, 128), (16, 256), (32, 512)
FOR j := 0 TO KL-1
    i := j * 16
    IF writemask_enabled:
        temp[31:0] := (SRC1.i16[j] * SRC2.i16[j]) >> 14 + 1
        DEST.i16[j] := tmp[16:1]
    ELSE if zero_masking:
        DEST.i16[j] = 0
DEST[MAXVL-1:VL] = 0
"""

handler = "x86_pmulhrsw"
jit_lowering = "arm64_neon_sqrdmulh"
fallback = "zig_lane_loop"

neon_register_model = """
x86 xmm/ymm lanes are mapped onto ARM64 v registers; lane width and MAXVL zero/merge rules are preserved by the lowering.
"""

neon_flag_model = """
No flags are written by PMULHRSW.
"""

neon_assembly = """
sqrdmulh vD.8h, vN.8h, vM.8h
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
