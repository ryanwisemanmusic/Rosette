// NEON/COMPUTE/PSADBW.inc
// ARM64/NEON mirror generated from ISA/x86/COMPUTE/PSADBW.inc.
// This file preserves the x86 source contract and supplies the ARM64 lowering contract.

semantic = """
PSADBW: preserve the operation and form-specific semantic blocks.
Category: simd_int.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "COMPUTE/PSADBW.inc"
x86_handler = "x86_psadbw"
neon_lowering = "arm64_psadbw"
lowering_kind = "arm64_documented_contract"

name = "PSADBW"
aliases = ["VPSADBW"]
category = "simd_int"
feature = "MMX_SSE2_AVX_AVX512BW"
element_type = "u16"
element_size = 16

encodings = [
  { opcode = "NP 0F F6 /r", form = "PSADBW mm1, mm2/m64", op_en = "A", feature = "MMX", vector_length = 64, encoding = "legacy" },
  { opcode = "66 0F F6 /r", form = "PSADBW xmm1, xmm2/m128", op_en = "A", feature = "SSE2", vector_length = 128, encoding = "legacy_sse" },
  { opcode = "VEX.128.66.0F.WIG F6 /r", form = "VPSADBW xmm1, xmm2, xmm3/m128", op_en = "B", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F.WIG F6 /r", form = "VPSADBW ymm1, ymm2, ymm3/m256", op_en = "B", feature = "AVX", vector_length = 256, encoding = "vex" },
  { opcode = "EVEX.512.66.0F.WIG F6 /r", form = "VPSADBW zmm1{k1}{z}, zmm2, zmm3/m512", op_en = "C", feature = "AVX512BW", vector_length = 512, encoding = "evex" },
  { opcode = "EVEX.256.66.0F.WIG F6 /r", form = "VPSADBW ymm1{k1}{z}, ymm2, ymm3/m256", op_en = "C", feature = "AVX512VL+AVX512BW", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.128.66.0F.WIG F6 /r", form = "VPSADBW xmm1{k1}{z}, xmm2, xmm3/m128", op_en = "C", feature = "AVX512VL+AVX512BW", vector_length = 128, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (r,w)", "ModRM:r/m (r)"],
  B = ["ModRM:reg (w)", "VEX.vvvv (r)", "ModRM:r/m (r)"],
  C = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)"]
}

lanes = { mmx = 1, xmm = 2, ymm = 4, zmm = 8 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "Non-VEX encoded instruction uses Type 4 class exception conditions",
  "VEX encoded instruction uses Type 4 class exception conditions",
  "EVEX encoded instruction uses Type E4 class exception conditions"
]

semantic_legacy_128 = """
DEST[15:0]   = SUM(ABS(SRC1[7:0]   - SRC2[7:0])    ... ABS(SRC1[63:56]  - SRC2[63:56]));
DEST[31:16]  = SUM(ABS(SRC1[71:64]  - SRC2[71:64])   ... ABS(SRC1[127:120] - SRC2[127:120]));
DEST[63:32]  = 0;
DEST[127:64] = 0;
DEST[MAXVL-1:128] unchanged;
"""

semantic_vex_128 = """
DEST[15:0]   = SUM(ABS(SRC1[7:0]   - SRC2[7:0])    ... ABS(SRC1[63:56]  - SRC2[63:56]));
DEST[31:16]  = SUM(ABS(SRC1[71:64]  - SRC2[71:64])   ... ABS(SRC1[127:120] - SRC2[127:120]));
DEST[63:32]  = 0;
DEST[127:64] = 0;
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
for j in 0..1:
    base = j * 128;
    DEST[base+15:base]   = SUM(ABS(SRC1[base+7:base]   - SRC2[base+7:base])    ... ABS(SRC1[base+63:base+56]  - SRC2[base+63:base+56]));
    DEST[base+31:base+16] = SUM(ABS(SRC1[base+71:base+64] - SRC2[base+71:base+64]) ... ABS(SRC1[base+127:base+120] - SRC2[base+127:base+120]));
    DEST[base+63:base+32] = 0;
    DEST[base+127:base+64] = 0;
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
(KL, VL) = (1,64), (2,128), (4,256), or (8,512);
for j in 0..KL-1:
    base = j * 64;
    if k1[j] == 1 or no_writemask:
        DEST[base+15:base]   = SUM(ABS(SRC1[base+7:base]   - SRC2[base+7:base])    ... ABS(SRC1[base+63:base+56]  - SRC2[base+63:base+56]));
        DEST[base+31:base+16] = SUM(ABS(SRC1[base+71:base+64] - SRC2[base+71:base+64]) ... ABS(SRC1[base+127:base+120] - SRC2[base+127:base+120]));
        DEST[base+63:base+32] = 0;
        DEST[base+127:base+64] = 0;
    else if zeroing_masking:
        DEST[base+127:base] = 0;
DEST[MAXVL-1:VL] = 0;
"""

handler = "x86_psadbw"
jit_lowering = "arm64_psadbw"
fallback = "zig_lane_loop_sad"

neon_register_model = """
x86 mmx/xmm/ymm/zmm byte lanes mapped to ARM64 V registers.
PSADBW sum-of-absolute-differences is lowered as UABDL + UADALP sequence.
"""

neon_flag_model = """
No x86 flags are modified by PSADBW/VPSADBW.
"""

neon_assembly = """
// NEON lowering: uabdl vD.8h, vN.8b, vM.8b; uadalp vD.4s, vD.8h
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, writemask, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
