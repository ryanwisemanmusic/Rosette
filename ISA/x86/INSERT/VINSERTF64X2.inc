// INSERT/VINSERTF64X2.inc
// ARM64/NEON translation mirror generated from ISA/x86/INSERT/VINSERTF64X2.inc.
// Source contract: VINSERTF64X2 — Insert Packed Double Precision Floating-Point Values.

// Canonical table metadata for registry-wide .inc validation.
semantic = """
VINSERTF64X2: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_insert.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INSERT/VINSERTF64X2.inc"
x86_handler = "x86_vinsertf64x2"
neon_lowering = "arm64_insert_f64x2_subvector"
lowering_kind = "arm64_documented_contract"

name = "VINSERTF64X2"
aliases = []
category = "simd_insert"
feature = "AVX512DQ_AVX512VL"
element_type = "f64x2_insert"
element_size = 128

encodings = [
  { opcode = "EVEX.256.66.0F3A.W1 18 /r ib", form = "VINSERTF64X2 ymm1 {k1}{z}, ymm2, xmm3/m128, imm8", op_en = "C", feature = "AVX512VL+AVX512DQ", vector_length = 256, encoding = "evex", broadcast = "m64bcst" },
  { opcode = "EVEX.512.66.0F3A.W1 18 /r ib", form = "VINSERTF64X2 zmm1 {k1}{z}, zmm2, xmm3/m128, imm8", op_en = "C", feature = "AVX512DQ", vector_length = 512, encoding = "evex", broadcast = "m64bcst" }
]

operand_encoding = {
  C = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)", "imm8"]
}

lanes = { ymm = 4, zmm = 8 }
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
CASE imm8[1:0] OF:
    0: DEST[127:0]    := SRC2[127:0];
       DEST[511:128]  := SRC1[511:128];
    1: DEST[255:128]  := SRC2[127:0];
       DEST[127:0]    := SRC1[127:0];
       DEST[511:256]  := SRC1[511:256];
    2: DEST[383:256]  := SRC2[127:0];
       DEST[255:0]    := SRC1[255:0];
       DEST[511:384]  := SRC1[511:384];
    3: DEST[511:384]  := SRC2[127:0];
       DEST[383:0]    := SRC1[383:0];
// with writemask and zero-masking per 128-bit lane
DEST[MAXVL-1:512] := 0;
"""

handler = "x86_vinsertf64x2"
jit_lowering = "arm64_insert_subvector"
fallback = "zig_insert_lane"

neon_register_model = """
x86 ymm/zmm double-precision lanes are mapped into ARM64 vector temporaries. VINSERTF64X2 inserts a 128-bit sub-vector from SRC2 into the destination at a 128-bit lane position selected by imm8.
"""

neon_flag_model = """
No x86 flags are modified by VINSERTF64X2.
"""

neon_assembly = """
// NEON lowering: for 256-bit, same as VINSERTF128 with double-precision mapping
// For 512-bit, treat zmm as four 128-bit NEON registers; select lane via imm8[1:0]
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, writemask, broadcast, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape.",
  "Broadcast support: when EVEX.b=1, SRC2 is broadcast from 64-bit memory."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
