// CMP/PCMPGTW.inc
// ARM64/NEON translation mirror generated from ISA/x86/CMP/PCMPGTW.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
PCMPGTW: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_integer_compare.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CMP/PCMPGTW.inc"
x86_handler = "x86_pcmpgtw"
neon_lowering = "arm64_documented_contract_pcmpgtw"
lowering_kind = "neon_vector"

name = "PCMPGTW"
aliases = ["VPCMPGTW"]
category = "simd_integer_compare"
feature = "MMX_SSE2_AVX_AVX2_AVX512BW"
element_type = "i16"
element_size = 16

encodings = [
  { opcode = "NP 0F 65 /r", form = "PCMPGTW mm, mm/m64", op_en = "A", feature = "MMX", vector_length = 64, encoding = "legacy_mmx" },
  { opcode = "66 0F 65 /r", form = "PCMPGTW xmm1, xmm2/m128", op_en = "A", feature = "SSE2", vector_length = 128, encoding = "legacy_sse" },
  { opcode = "VEX.128.66.0F.WIG 65 /r", form = "VPCMPGTW xmm1, xmm2, xmm3/m128", op_en = "B", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F.WIG 65 /r", form = "VPCMPGTW ymm1, ymm2, ymm3/m256", op_en = "B", feature = "AVX2", vector_length = 256, encoding = "vex" },
  { opcode = "EVEX.128.66.0F.WIG 65 /r", form = "VPCMPGTW xmm1 {k1}{z}, xmm2, xmm3/m128", op_en = "C", feature = "AVX512VL+AVX512BW", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F.WIG 65 /r", form = "VPCMPGTW ymm1 {k1}{z}, ymm2, ymm3/m256", op_en = "C", feature = "AVX512VL+AVX512BW", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F.WIG 65 /r", form = "VPCMPGTW zmm1 {k1}{z}, zmm2, zmm3/m512", op_en = "C", feature = "AVX512BW", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (r,w)", "ModRM:r/m (r)"],
  B = ["ModRM:reg (w)", "VEX.vvvv (r)", "ModRM:r/m (r)"],
  C = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)"]
}

lanes = { mm = 4, xmm = 8, ymm = 16, zmm = 32 }
flags_written = []
mxcsr_used = false

simd_fp_exceptions = []

semantic_legacy_64 = """
for word in 0..4:
    if DEST.i16[word] > SRC.i16[word]:     # signed greater-than
        DEST.i16[word] = -1;
    else:
        DEST.i16[word] = 0;
"""

semantic_legacy_128 = """
for word in 0..8:
    if DEST.i16[word] > SRC.i16[word]:     # signed greater-than
        DEST.i16[word] = -1;
    else:
        DEST.i16[word] = 0;
DEST[MAXVL-1:128] unchanged;
"""

semantic_vex_128 = """
for word in 0..8:
    if SRC1.i16[word] > SRC2.i16[word]:   # signed greater-than
        DEST.i16[word] = -1;
    else:
        DEST.i16[word] = 0;
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
for word in 0..16:
    if SRC1.i16[word] > SRC2.i16[word]:   # signed greater-than
        DEST.i16[word] = -1;
    else:
        DEST.i16[word] = 0;
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
(KL, VL) = (8, 128), (16, 256), (32, 512);
for each active word lane selected by k2 or no writemask:
    if SRC1.i16[lane] > SRC2.i16[lane]:   # signed greater-than
        DEST.i16[lane] = -1;
    else:
        DEST.i16[lane] = 0;
DEST[MAXVL-1:VL] = 0;
"""

handler = "x86_pcmpgtw"
jit_lowering = "arm64_documented_contract_pcmpgtw"
fallback = "zig_lane_loop_icmp_gt_w"

neon_register_model = """
x86 MMX/XMM/YMM/ZMM word lanes are mapped onto ARM64 v registers; each lane yields an all-1s/all-0s mask per signed word comparison.
"""

neon_flag_model = """
No x86 flags are modified; no MXCSR side-effects occur.
"""

neon_assembly = """
// ARM64 NEON provides CMGT for signed 16-bit element-wise greater-than comparison.
//     cmgt vD.8h, vN.8h, vM.8h
// The result is an all-1s or all-0s mask per word lane (signed comparison).
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, writemask, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
