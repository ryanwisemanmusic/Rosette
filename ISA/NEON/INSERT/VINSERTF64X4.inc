// INSERT/VINSERTF64X4.inc
// ARM64/NEON mirror generated from ISA/x86/INSERT/VINSERTF64X4.inc.
// This file preserves the x86 source contract and supplies the ARM64 lowering contract.

// Canonical table metadata for registry-wide .inc validation.
semantic = """
VINSERTF64X4: Insert a 256-bit floating-point lane from a YMM source register or memory into a ZMM destination at a specified 256-bit position, with optional writemask.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_insertion.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INSERT/VINSERTF64X4.inc"
x86_handler = "x86_vinsertf64x4"
neon_lowering = "arm64_neon_insert_f64x4"
lowering_kind = "arm64_documented_contract"

// INSERT/VINSERTF64X4.inc
// ARM64/NEON translation mirror generated from ISA/x86/INSERT/VINSERTF64X4.inc.
// Source contract: VINSERTF64X4 — Insert 256-bit Packed Double-Precision Floating-Point Lane.

name = "VINSERTF64X4"
aliases = []
category = "simd_insertion"
feature = "AVX512DQ"
element_type = "f64_bits"
element_size = 256

encodings = [
  { opcode = "EVEX.512.66.0F3A.W1 1A /r ib", form = "VINSERTF64X4 zmm1{k1}{z}, zmm2, ymm3/m256, imm8", op_en = "C", feature = "AVX512DQ", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  C = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)", "imm8 (r)"]
}

lanes = { zmm = 2 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "EVEX encoded instruction uses Type E4 class exception conditions"
]

semantic_evex = """
// imm8[0] selects the 256-bit lane position (0-lower, 1-upper)
// Semantics match VINSERTF32X8 but lanes carry packed double-precision elements
(KL, VL) = (2, 512);
lane_idx = imm8[0];
SRC2_width = 256;
for j in 0..1:
    i = j * 256;
    if k1[j*4 .. j*4+3] == 1's or no_writemask:
        if j == lane_idx:
            DEST[i+255:i] = SRC2[255:0];
        else:
            DEST[i+255:i] = SRC1[i+255:i];
    else if zeroing_masking:
        DEST[i+255:i] = 0;
DEST[MAXVL-1:512] = 0;
"""

handler = "x86_vinsertf64x4"
jit_lowering = "arm64_neon_insert_f64x4"
fallback = "zig_lane_insert_256"

neon_register_model = """
x86 zmm registers are mapped into ARM64 vector temporaries via pairs of 128-bit NEON registers. The 256-bit lane insertion selects between the upper and lower halves of the register pair.
"""

neon_flag_model = """
No x86 flags are modified by VINSERTF64X4.
"""

neon_assembly = """
// VINSERTF64X4: insert 256-bit double-precision lane at position imm8[0]
// ARM64: 256-bit lane select between halves of 512-bit register pair
// imm8[0] == 0: vD_lo = vN[255:0]; vD_hi = vM[255:0] (from SRC1)
// imm8[0] == 1: vD_lo = vM[255:0] (from SRC1); vD_hi = vN[255:0]
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, writemask, broadcast, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
