// MUL/PMULUDQ.inc
// ARM64/NEON translation mirror generated from ISA/x86/MUL/PMULUDQ.inc.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
PMULUDQ: preserve the operation and form-specific semantic blocks.
Category: simd_int_mul.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "MUL/PMULUDQ.inc"
x86_handler = "x86_pmuludq"
neon_lowering = "arm64_neon_umull_v2i32"
lowering_kind = "neon_vector"

name = "PMULUDQ"
category = "simd_int_mul"
feature = "SSE2"
element_type = "u32"

encodings = [
  { opcode = "NP 0F F4 /r", form = "PMULUDQ mm1, mm2/m64", op_en = "A", feature = "SSE2" },
  { opcode = "66 0F F4 /r", form = "PMULUDQ xmm1, xmm2/m128", op_en = "A", feature = "SSE2" },
  { opcode = "VEX.128.66.0F.WIG F4 /r", form = "VPMULUDQ xmm1, xmm2, xmm3/m128", op_en = "B", feature = "AVX" },
  { opcode = "VEX.256.66.0F.WIG F4 /r", form = "VPMULUDQ ymm1, ymm2, ymm3/m256", op_en = "B", feature = "AVX2" },
  { opcode = "EVEX.128.66.0F.WIG F4 /r", form = "VPMULUDQ xmm1 {k1}{z}, xmm2, xmm3/m128", op_en = "C", feature = "AVX512F AVX512VL" },
  { opcode = "EVEX.256.66.0F.WIG F4 /r", form = "VPMULUDQ ymm1 {k1}{z}, ymm2, ymm3/m256", op_en = "C", feature = "AVX512F AVX512VL" },
  { opcode = "EVEX.512.66.0F.WIG F4 /r", form = "VPMULUDQ zmm1 {k1}{z}, zmm2, zmm3/m512", op_en = "C", feature = "AVX512F" },
]

element_size = 32
lane_type = "dword"

lanes = {
  mmx = 2,
  xmm = 2,
  ymm = 4,
  zmm = 8
}

mxcsr_used = false

simd_fp_exceptions = []

flags_written = []

semantic_legacy_128 = """
DEST.u64[0] = DEST.u32[0] * SRC.u32[0];
DEST.u64[1] = DEST.u32[2] * SRC.u32[2];
DEST[MAXVL-1:128] unchanged;
"""

semantic_vex_128 = """
DEST.u64[0] = SRC1.u32[0] * SRC2.u32[0];
DEST.u64[1] = SRC1.u32[2] * SRC2.u32[2];
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
DEST.u64[0] = SRC1.u32[0] * SRC2.u32[0];
DEST.u64[1] = SRC1.u32[2] * SRC2.u32[2];
DEST.u64[2] = SRC1.u32[4] * SRC2.u32[4];
DEST.u64[3] = SRC1.u32[6] * SRC2.u32[6];
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
for lane in VL qwords:
    if writemask_enabled:
        DEST.u64[lane] = SRC1.u32[lane*2] * SRC2.u32[lane*2];
    else if zero_masking:
        DEST.u64[lane] = 0;
DEST[MAXVL-1:VL] = 0;
"""

handler = "x86_pmuludq"
jit_lowering = "arm64_neon_umull_v2i32"
fallback = "zig_lane_loop"

neon_register_model = """
x86 xmm/ymm lanes are mapped onto ARM64 v registers; lane width and MAXVL zero/merge rules are preserved by the lowering.
"""

neon_flag_model = """
No flags are written by PMULUDQ.
"""

neon_assembly = """
umull vD.2d, vN.2s, vM.2s
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
