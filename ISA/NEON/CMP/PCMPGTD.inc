// CMP/PCMPGTD.inc
// ARM64/NEON translation mirror generated from ISA/x86/CMP/PCMPGTD.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
PCMPGTD: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_integer_compare.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CMP/PCMPGTD.inc"
x86_handler = "x86_pcmpgtd"
neon_lowering = "arm64_documented_contract_pcmpgtd"
lowering_kind = "neon_vector"

name = "PCMPGTD"
aliases = ["VPCMPGTD"]
category = "simd_integer_compare"
feature = "MMX_SSE2_AVX_AVX2_AVX512F"
element_type = "i32"
element_size = 32

encodings = [
  { opcode = "NP 0F 66 /r", form = "PCMPGTD mm, mm/m64", op_en = "A", feature = "MMX", vector_length = 64, encoding = "legacy_mmx" },
  { opcode = "66 0F 66 /r", form = "PCMPGTD xmm1, xmm2/m128", op_en = "A", feature = "SSE2", vector_length = 128, encoding = "legacy_sse" },
  { opcode = "VEX.128.66.0F.WIG 66 /r", form = "VPCMPGTD xmm1, xmm2, xmm3/m128", op_en = "B", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F.WIG 66 /r", form = "VPCMPGTD ymm1, ymm2, ymm3/m256", op_en = "B", feature = "AVX2", vector_length = 256, encoding = "vex" },
  { opcode = "EVEX.128.66.0F.W0 66 /r", form = "VPCMPGTD xmm1 {k1}{z}, xmm2, xmm3/m128/m32bcst", op_en = "C", feature = "AVX512VL+AVX512F", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F.W0 66 /r", form = "VPCMPGTD ymm1 {k1}{z}, ymm2, ymm3/m256/m32bcst", op_en = "C", feature = "AVX512VL+AVX512F", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F.W0 66 /r", form = "VPCMPGTD zmm1 {k1}{z}, zmm2, zmm3/m512/m32bcst", op_en = "C", feature = "AVX512F", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (r,w)", "ModRM:r/m (r)"],
  B = ["ModRM:reg (w)", "VEX.vvvv (r)", "ModRM:r/m (r)"],
  C = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)"]
}

lanes = { mm = 2, xmm = 4, ymm = 8, zmm = 16 }
flags_written = []
mxcsr_used = false

simd_fp_exceptions = []

semantic_legacy_64 = """
for dword in 0..2:
    if DEST.i32[dword] > SRC.i32[dword]:     # signed greater-than
        DEST.i32[dword] = -1;
    else:
        DEST.i32[dword] = 0;
"""

semantic_legacy_128 = """
for dword in 0..4:
    if DEST.i32[dword] > SRC.i32[dword]:     # signed greater-than
        DEST.i32[dword] = -1;
    else:
        DEST.i32[dword] = 0;
DEST[MAXVL-1:128] unchanged;
"""

semantic_vex_128 = """
for dword in 0..4:
    if SRC1.i32[dword] > SRC2.i32[dword]:   # signed greater-than
        DEST.i32[dword] = -1;
    else:
        DEST.i32[dword] = 0;
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
for dword in 0..8:
    if SRC1.i32[dword] > SRC2.i32[dword]:   # signed greater-than
        DEST.i32[dword] = -1;
    else:
        DEST.i32[dword] = 0;
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
(KL, VL) = (4, 128), (8, 256), (16, 512);
for each active dword lane selected by k2 or no writemask:
    if SRC1.i32[lane] > SRC2.i32[lane_or_broadcast]:   # signed greater-than
        DEST.i32[lane] = -1;
    else:
        DEST.i32[lane] = 0;
DEST[MAXVL-1:VL] = 0;
"""

handler = "x86_pcmpgtd"
jit_lowering = "arm64_documented_contract_pcmpgtd"
fallback = "zig_lane_loop_icmp_gt_d"

neon_register_model = """
x86 MMX/XMM/YMM/ZMM dword lanes are mapped onto ARM64 v registers; each lane yields an all-1s/all-0s mask per signed 32-bit comparison.
"""

neon_flag_model = """
No x86 flags are modified; no MXCSR side-effects occur.
"""

neon_assembly = """
// ARM64 NEON provides CMGT for signed 32-bit element-wise greater-than comparison.
//     cmgt vD.4s, vN.4s, vM.4s
// The result is an all-1s or all-0s mask per dword lane (signed comparison).
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, writemask, broadcast, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
