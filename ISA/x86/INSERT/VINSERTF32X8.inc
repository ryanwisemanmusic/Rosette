// INSERT/VINSERTF32X8.inc
// ARM64/NEON translation mirror generated from ISA/x86/INSERT/VINSERTF32X8.inc.
// Source contract: VINSERTF32X8 — Insert Eight Packed Single Precision Floating-Point Values.

// Canonical table metadata for registry-wide .inc validation.
semantic = """
VINSERTF32X8: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_insert.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INSERT/VINSERTF32X8.inc"
x86_handler = "x86_vinsertf32x8"
neon_lowering = "arm64_insert_f32x8_subvector"
lowering_kind = "arm64_documented_contract"

name = "VINSERTF32X8"
aliases = []
category = "simd_insert"
feature = "AVX512DQ"
element_type = "f32x8_insert"
element_size = 256

encodings = [
  { opcode = "EVEX.512.66.0F3A.W0 1A /r ib", form = "VINSERTF32X8 zmm1 {k1}{z}, zmm2, ymm3/m256, imm8", op_en = "C", feature = "AVX512DQ", vector_length = 512, encoding = "evex", broadcast = "m32bcst" }
]

operand_encoding = {
  C = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)", "imm8"]
}

lanes = { zmm = 16 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "EVEX encoded instruction uses Type E4 class exception conditions"
]

semantic_evex_512 = """
CASE imm8[0] OF:
    0: DEST[255:0]   := SRC2[255:0];
       DEST[511:256] := SRC1[511:256];
    1: DEST[255:0]   := SRC1[255:0];
       DEST[511:256] := SRC2[255:0];
// with writemask and zero-masking per 256-bit lane
DEST[MAXVL-1:512] := 0;
"""

handler = "x86_vinsertf32x8"
jit_lowering = "arm64_insert_subvector"
fallback = "zig_insert_lane"

neon_register_model = """
x86 zmm single-precision lanes are mapped into ARM64 vector temporaries. VINSERTF32X8 inserts a 256-bit sub-vector from SRC2 into the low or high half of the destination ZMM register, selected by imm8[0].
"""

neon_flag_model = """
No x86 flags are modified by VINSERTF32X8.
"""

neon_assembly = """
// NEON lowering: treat zmm as four 128-bit NEON registers
// VINSERTF32X8 selects a 256-bit (two 128-bit) lane via imm8[0]
// Implemented via mov/ins across paired 128-bit temporaries
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, writemask, broadcast, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape.",
  "512-bit ZMM is lowered as four 128-bit NEON registers."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
