// LOAD/VPBROADCASTW.inc
// VPBROADCASTW — Broadcast word integer from source to all elements.

source_isa = "x86"
target_isa = "x86"
x86_table = "LOAD/VPBROADCASTW.inc"
x86_handler = "x86_vpbroadcastw"
neon_lowering = "arm64_neon_dup_h"
lowering_kind = "neon_vector"

name = "VPBROADCASTW"
aliases = []
category = "simd_broadcast_integer"
feature = "AVX2_AVX512BW"
element_type = "i16"
element_size = 16

encodings = [
  { opcode = "VEX.128.66.0F38.W0 79 /r", form = "VPBROADCASTW xmm1, xmm2/m16", op_en = "A", feature = "AVX2", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F38.W0 79 /r", form = "VPBROADCASTW ymm1, xmm2/m16", op_en = "A", feature = "AVX2", vector_length = 256, encoding = "vex" },
  { opcode = "EVEX.128.66.0F38.W0 79 /r", form = "VPBROADCASTW xmm1{k1}{z}, xmm2/m16", op_en = "B", feature = "AVX512VL+AVX512BW", vector_length = 128, encoding = "evex", broadcast = "tuple1_scalar" },
  { opcode = "EVEX.256.66.0F38.W0 79 /r", form = "VPBROADCASTW ymm1{k1}{z}, xmm2/m16", op_en = "B", feature = "AVX512VL+AVX512BW", vector_length = 256, encoding = "evex", broadcast = "tuple1_scalar" },
  { opcode = "EVEX.512.66.0F38.W0 79 /r", form = "VPBROADCASTW zmm1{k1}{z}, xmm2/m16", op_en = "B", feature = "AVX512BW", vector_length = 512, encoding = "evex", broadcast = "tuple1_scalar" },
  { opcode = "EVEX.128.66.0F38.W0 7B /r", form = "VPBROADCASTW xmm1{k1}{z}, reg", op_en = "A", feature = "AVX512VL+AVX512BW", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F38.W0 7B /r", form = "VPBROADCASTW ymm1{k1}{z}, reg", op_en = "A", feature = "AVX512VL+AVX512BW", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F38.W0 7B /r", form = "VPBROADCASTW zmm1{k1}{z}, reg", op_en = "A", feature = "AVX512BW", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "ModRM:r/m (r)"],
  B = ["ModRM:reg (w)", "ModRM:r/m (r)"]
}

lanes = { xmm = 8, ymm = 16, zmm = 32 }
flags_written = []
semantic = """
VPBROADCASTW broadcasts the selected 16-bit source element to every destination
word lane and clears the upper portion of the architectural vector when using
the VEX form.
"""
simd_fp_exceptions = []
other_exceptions = [
  "EVEX-encoded instructions use Type E6 class exception conditions",
  "GPR-source EVEX-encoded instructions use Type E7NM class exception conditions",
  "If VEX.vvvv != 1111B or EVEX.vvvv != 1111B, #UD"
]

semantic_legacy_128 = """
DEST[15:0]  = SRC[15:0];
...broadcast to all 8 word positions;
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
DEST[15:0]  = SRC[15:0];
...broadcast to all 16 word positions;
DEST[MAXVL-1:256] = 0;
"""

semantic_evex = """
(KL, VL) = (8,128), (16,256), (32,512);
FOR j := 0 TO KL-1
    i := j * 16;
    IF k1[j] OR *no writemask*
        THEN DEST[i+15:i] := SRC[15:0]
        ELSE
            IF *merging-masking*
                THEN *DEST[i+15:i] remains unchanged*
                ELSE DEST[i+15:i] := 0
            FI
    FI;
ENDFOR;
DEST[MAXVL-1:VL] := 0;
"""

handler = "x86_vpbroadcastw"
jit_lowering = "arm64_neon_dup_h"
fallback = "zig_lane_loop_broadcast_16"

neon_register_model = """
x86 xmm/ymm/zmm word lanes are mapped into ARM64 vector temporaries. VPBROADCASTW uses DUP (element) to broadcast a 16-bit value to all word positions.
"""

neon_flag_model = """
No x86 flags are modified by VPBROADCASTW.
"""

neon_assembly = """
dup vD.8h, wN
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, writemask, broadcast, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
