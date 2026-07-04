// INSERT/VINSERTF32X4.inc
// ARM64/NEON translation mirror generated from ISA/x86/INSERT/VINSERTF32X4.inc.
// Source contract: VINSERTF32X4 — Insert Packed Single Precision Floating-Point Values.

// Canonical table metadata for registry-wide .inc validation.
semantic = """
VINSERTF32X4: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_insert.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INSERT/VINSERTF32X4.inc"
x86_handler = "x86_vinsertf32x4"
neon_lowering = "arm64_insert_f32x4_subvector"
lowering_kind = "arm64_documented_contract"

name = "VINSERTF32X4"
aliases = []
category = "simd_insert"
feature = "AVX512F_AVX512VL"
element_type = "f32x4_insert"
element_size = 128

encodings = [
  { opcode = "EVEX.256.66.0F3A.W0 18 /r ib", form = "VINSERTF32X4 ymm1 {k1}{z}, ymm2, xmm3/m128, imm8", op_en = "C", feature = "AVX512VL+AVX512F", vector_length = 256, encoding = "evex", broadcast = "m32bcst" },
  { opcode = "EVEX.512.66.0F3A.W0 18 /r ib", form = "VINSERTF32X4 zmm1 {k1}{z}, zmm2, xmm3/m128, imm8", op_en = "C", feature = "AVX512F", vector_length = 512, encoding = "evex", broadcast = "m32bcst" }
]

operand_encoding = {
  C = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)", "imm8"]
}

lanes = { ymm = 8, zmm = 16 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "EVEX encoded instruction uses Type E4 class exception conditions",
  "#UD If EVEX.L′L != 01 for 256-bit or 10 for 512-bit."
]

semantic_evex_256 = """
CASE imm8[0] OF:
    0: DEST[127:0]   := SRC2[127:0];
       DEST[255:128] := SRC1[255:128];
    1: DEST[127:0]   := SRC1[127:0];
       DEST[255:128] := SRC2[127:0];
// with writemask and zero-masking per 128-bit lane
DEST[MAXVL-1:256] := 0;
"""

semantic_evex_512 = """
SRC2_128 := SRC2[127:0]; // source sub-vector is always 128-bit
CASE imm8[1:0] OF:
    0: DEST[127:0]    := SRC2_128;
       DEST[511:128]  := SRC1[511:128];
    1: DEST[255:128]  := SRC2_128;
       DEST[127:0]    := SRC1[127:0];
       DEST[511:256]  := SRC1[511:256];
    2: DEST[383:256]  := SRC2_128;
       DEST[255:0]    := SRC1[255:0];
       DEST[511:384]  := SRC1[511:384];
    3: DEST[511:384]  := SRC2_128;
       DEST[383:0]    := SRC1[383:0];
// with writemask and zero-masking per 128-bit lane
DEST[MAXVL-1:512] := 0;
"""

handler = "x86_vinsertf32x4"
jit_lowering = "arm64_insert_subvector"
fallback = "zig_insert_lane"

neon_register_model = """
x86 ymm/zmm floating-point lanes are mapped into ARM64 vector temporaries. VINSERTF32X4 inserts a 128-bit sub-vector from SRC2 into the destination at a 128-bit lane position selected by imm8.
"""

neon_flag_model = """
No x86 flags are modified by VINSERTF32X4.
"""

neon_assembly = """
// NEON lowering: for 256-bit, same as VINSERTF128 with writemask support
// For 512-bit, treat zmm as four 128-bit NEON registers; select lane via imm8[1:0]
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, writemask, broadcast, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape.",
  "Broadcast support: when EVEX.b=1, SRC2 is broadcast from 32-bit memory."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
