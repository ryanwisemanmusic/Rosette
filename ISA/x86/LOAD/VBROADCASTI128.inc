// LOAD/VBROADCASTI128.inc
// VBROADCASTI128 — Broadcast 128 bits of integer data to both halves of ymm.

source_isa = "x86"
target_isa = "x86"
x86_table = "LOAD/VBROADCASTI128.inc"
x86_handler = "x86_vbroadcasti128"
neon_lowering = "arm64_neon_dup_128_to_256"
lowering_kind = "neon_vector"

name = "VBROADCASTI128"
aliases = []
category = "simd_broadcast_integer"
feature = "AVX2"
element_type = "i32_bits"
element_size = 128

encodings = [
  { opcode = "VEX.256.66.0F38.W0 5A /r", form = "VBROADCASTI128 ymm1, m128", op_en = "A", feature = "AVX2", vector_length = 256, encoding = "vex" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "ModRM:r/m (r)"]
}

lanes = { ymm = 2 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "If VEX.L = 0, #UD",
  "If VEX.vvvv != 1111B, #UD",
  "Register source encoding is reserved and will #UD"
]

semantic_vex_256 = """
temp := SRC[127:0];
DEST[127:0] := temp;
DEST[255:128] := temp;
DEST[MAXVL-1:256] := 0;
"""

handler = "x86_vbroadcasti128"
jit_lowering = "arm64_neon_dup_128_to_256"
fallback = "zig_lane_loop_broadcast_128"

neon_register_model = """
x86 ymm lanes are mapped into a pair of ARM64 128-bit vector registers. VBROADCASTI128 duplicates 128-bit memory data into both halves of ymm.
"""

neon_flag_model = """
No x86 flags are modified by VBROADCASTI128.
"""

neon_assembly = """
ldr qTMP, [xSRC]
; mov vD.16b, vTMP.16b
; ins vD.d[1], vTMP.d[0]  -- replicate lower 128 bits into upper 128 bits
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, writemask, broadcast, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

semantic_general = """
VBROADCASTI128: preserve the x86 operation contract; see the x86 source table for the full semantic blocks.
"""

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
