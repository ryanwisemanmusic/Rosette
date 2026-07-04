// INSERT/VINSERTF64X2.inc
// ARM64/NEON mirror generated from ISA/x86/INSERT/VINSERTF64X2.inc.
// This file preserves the x86 source contract and supplies the ARM64 lowering contract.

// Canonical table metadata for registry-wide .inc validation.
semantic = """
VINSERTF64X2: Insert a 128-bit floating-point lane from an XMM source register or memory into a YMM/ZMM destination at a specified 128-bit position, with optional writemask and broadcast.
See operation, semantic_* blocks, source_contract, or preserved X86_INST rows below for the full instruction behavior.
Category: simd_insertion.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INSERT/VINSERTF64X2.inc"
x86_handler = "x86_vinsertf64x2"
neon_lowering = "arm64_neon_insert_f64x2"
lowering_kind = "arm64_documented_contract"

// INSERT/VINSERTF64X2.inc
// ARM64/NEON translation mirror generated from ISA/x86/INSERT/VINSERTF64X2.inc.
// Source contract: VINSERTF64X2 — Insert 128-bit Packed Double-Precision Floating-Point Lane.

name = "VINSERTF64X2"
aliases = []
category = "simd_insertion"
feature = "AVX512F"
element_type = "f64_bits"
element_size = 128

encodings = [
  { opcode = "EVEX.256.66.0F3A.W1 18 /r ib", form = "VINSERTF64X2 ymm1{k1}{z}, ymm2, xmm3/m128, imm8", op_en = "C", feature = "AVX512VL+AVX512F", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F3A.W1 18 /r ib", form = "VINSERTF64X2 zmm1{k1}{z}, zmm2, xmm3/m128, imm8", op_en = "C", feature = "AVX512F", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  C = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)", "imm8 (r)"]
}

lanes = { ymm = 2, zmm = 4 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "EVEX encoded instruction uses Type E4 class exception conditions"
]

semantic_evex = """
// imm8[0] selects the 128-bit lane position for VL=256
// imm8[1:0] selects the 128-bit lane position for VL=512
// Semantics identical to VINSERTF32X4 but operates on packed double-precision lanes
(KL, VL) = (2,256) or (4,512);
lane_idx = imm8[log2(KL)-1:0];
for j in 0..KL-1:
    i = j * 128;
    if k1[j*2 .. j*2+1] == 1's or no_writemask:
        if j == lane_idx:
            DEST[i+127:i] = SRC2[127:0];
        else:
            DEST[i+127:i] = SRC1[i+127:i];
    else if zeroing_masking:
        DEST[i+127:i] = 0;
DEST[MAXVL-1:VL] = 0;
"""

handler = "x86_vinsertf64x2"
jit_lowering = "arm64_neon_insert_f64x2"
fallback = "zig_lane_insert_128"

neon_register_model = """
x86 ymm/zmm registers are mapped into ARM64 vector temporaries. The 128-bit lane insertion semantics match VINSERTF32X4 but the operands are treated as packed double-precision lanes.
"""

neon_flag_model = """
No x86 flags are modified by VINSERTF64X2.
"""

neon_assembly = """
// VINSERTF64X2: insert 128-bit double-precision lane at position imm8[log2(KL)-1:0]
// ARM64: vector extract or subregister insert with writemask handling
// VL=256: vD = VECTOR_SET_128_LANE(vD, imm8[0], vN)
// VL=512: vD = VECTOR_SET_128_LANE(vD, imm8[1:0], vN)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, writemask, broadcast, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
