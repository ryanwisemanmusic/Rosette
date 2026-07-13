// CMP/PCMPEQB.inc
// ARM64/NEON translation mirror generated from ISA/x86/CMP/PCMPEQB.inc.
// This file preserves the full x86 instruction contract, then appends the ARM64/NEON lowering contract.

// Canonical table metadata for registry-wide .inc validation.
operand_encoding = [
  { op_en = "DOC", operand_1 = "see preserved_source_contract", operand_2 = "see preserved_source_contract", operand_3 = "N/A", operand_4 = "N/A" },
]
semantic = """
PCMPEQB: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_integer_compare.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CMP/PCMPEQB.inc"
x86_handler = "x86_pcmpeqb"
neon_lowering = "arm64_documented_contract_pcmpeqb"
lowering_kind = "neon_vector"

name = "PCMPEQB"
aliases = ["VPCMPEQB"]
category = "simd_integer_compare"
feature = "MMX_SSE2_AVX_AVX2_AVX512BW"
element_type = "i8"
element_size = 8

encodings = [
  { opcode = "NP 0F 74 /r", form = "PCMPEQB mm, mm/m64", op_en = "A", feature = "MMX", vector_length = 64, encoding = "legacy_mmx" },
  { opcode = "66 0F 74 /r", form = "PCMPEQB xmm1, xmm2/m128", op_en = "A", feature = "SSE2", vector_length = 128, encoding = "legacy_sse" },
  { opcode = "VEX.128.66.0F.WIG 74 /r", form = "VPCMPEQB xmm1, xmm2, xmm3/m128", op_en = "B", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F.WIG 74 /r", form = "VPCMPEQB ymm1, ymm2, ymm3/m256", op_en = "B", feature = "AVX2", vector_length = 256, encoding = "vex" },
  { opcode = "EVEX.128.66.0F.WIG 74 /r", form = "VPCMPEQB xmm1 {k1}{z}, xmm2, xmm3/m128", op_en = "C", feature = "AVX512VL+AVX512BW", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F.WIG 74 /r", form = "VPCMPEQB ymm1 {k1}{z}, ymm2, ymm3/m256", op_en = "C", feature = "AVX512VL+AVX512BW", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F.WIG 74 /r", form = "VPCMPEQB zmm1 {k1}{z}, zmm2, zmm3/m512", op_en = "C", feature = "AVX512BW", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (r,w)", "ModRM:r/m (r)"],
  B = ["ModRM:reg (w)", "VEX.vvvv (r)", "ModRM:r/m (r)"],
  C = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)"]
}

lanes = { mm = 8, xmm = 16, ymm = 32, zmm = 64 }
flags_written = []
mxcsr_used = false

simd_fp_exceptions = []

semantic_legacy_64 = """
for byte in 0..8:
    if DEST.i8[byte] == SRC.i8[byte]:
        DEST.i8[byte] = -1;
    else:
        DEST.i8[byte] = 0;
"""

semantic_legacy_128 = """
for byte in 0..16:
    if DEST.i8[byte] == SRC.i8[byte]:
        DEST.i8[byte] = -1;
    else:
        DEST.i8[byte] = 0;
DEST[MAXVL-1:128] unchanged;
"""

semantic_vex_128 = """
for byte in 0..16:
    if SRC1.i8[byte] == SRC2.i8[byte]:
        DEST.i8[byte] = -1;
    else:
        DEST.i8[byte] = 0;
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
for byte in 0..32:
    if SRC1.i8[byte] == SRC2.i8[byte]:
        DEST.i8[byte] = -1;
    else:
        DEST.i8[byte] = 0;
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
(KL, VL) = (16, 128), (32, 256), (64, 512);
for each active byte lane selected by k2 or no writemask:
    if SRC1.i8[lane] == SRC2.i8[lane]:
        DEST.i8[lane] = -1;
    else:
        DEST.i8[lane] = 0;
DEST[MAXVL-1:VL] = 0;
"""

handler = "x86_pcmpeqb"
jit_lowering = "arm64_documented_contract_pcmpeqb"
fallback = "zig_lane_loop_icmp_eq_b"

neon_register_model = """
x86 MMX/XMM/YMM/ZMM byte lanes are mapped onto ARM64 v registers; each lane yields an all-1s/all-0s result per byte element.
"""

neon_flag_model = """
No x86 flags are modified; no MXCSR side-effects occur.
"""

neon_assembly = """
// ARM64 NEON provides CMEQ for byte-wise equality comparison.
//     cmeq vD.16b, vN.16b, vM.16b
// The result is an all-1s or all-0s mask per byte lane.
// For 8-byte MMX or wider 32/64-byte vectors, the operation is repeated per 16-byte register group.
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, writemask, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
