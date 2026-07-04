// INSERT/VINSERTI64X4.inc
// ARM64/NEON translation mirror generated from ISA/x86/INSERT/VINSERTI64X4.inc.
// Source contract: VINSERTI64X4 — Insert Four Packed Integer Values.

// Canonical table metadata for registry-wide .inc validation.
semantic = """
VINSERTI64X4: preserve the operation and form-specific semantic blocks.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_insert.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INSERT/VINSERTI64X4.inc"
x86_handler = "x86_vinserti64x4"
neon_lowering = "arm64_insert_i64x4_subvector"
lowering_kind = "arm64_documented_contract"

name = "VINSERTI64X4"
aliases = []
category = "simd_insert"
feature = "AVX512F"
element_type = "i64x4_insert"
element_size = 256

encodings = [
  { opcode = "EVEX.512.66.0F3A.W1 3A /r ib", form = "VINSERTI64X4 zmm1 {k1}{z}, zmm2, ymm3/m256, imm8", op_en = "C", feature = "AVX512F", vector_length = 512, encoding = "evex", broadcast = "m64bcst" }
]

operand_encoding = {
  C = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)", "imm8"]
}

lanes = { zmm = 8 }
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

handler = "x86_vinserti64x4"
jit_lowering = "arm64_insert_subvector"
fallback = "zig_insert_lane"

neon_register_model = """
x86 zmm integer qword lanes are mapped into ARM64 vector temporaries. VINSERTI64X4 inserts a 256-bit sub-vector from SRC2 into the low or high half of the destination ZMM register, selected by imm8[0].
"""

neon_flag_model = """
No x86 flags are modified by VINSERTI64X4.
"""

neon_assembly = """
// NEON lowering: treat zmm as four 128-bit NEON registers
// VINSERTI64X4 selects a 256-bit (two 128-bit) lane via imm8[0]
// Implemented via mov/ins across paired 128-bit temporaries
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, writemask, broadcast, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape.",
  "Broadcast support: when EVEX.b=1, SRC2 is broadcast from 64-bit memory."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
