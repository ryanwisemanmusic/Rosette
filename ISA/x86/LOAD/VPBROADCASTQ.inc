// LOAD/VPBROADCASTQ.inc
// VPBROADCASTQ — Broadcast qword integer from source to all elements.

source_isa = "x86"
target_isa = "x86"
x86_table = "LOAD/VPBROADCASTQ.inc"
x86_handler = "x86_vpbroadcastq"
neon_lowering = "arm64_neon_dup_d"
lowering_kind = "neon_vector"

name = "VPBROADCASTQ"
aliases = []
category = "simd_broadcast_integer"
feature = "AVX2_AVX512F"
element_type = "i64"
element_size = 64

encodings = [
  { opcode = "VEX.128.66.0F38.W0 59 /r", form = "VPBROADCASTQ xmm1, xmm2/m64", op_en = "A", feature = "AVX2", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F38.W0 59 /r", form = "VPBROADCASTQ ymm1, xmm2/m64", op_en = "A", feature = "AVX2", vector_length = 256, encoding = "vex" },
  { opcode = "EVEX.128.66.0F38.W1 59 /r", form = "VPBROADCASTQ xmm1{k1}{z}, xmm2/m64", op_en = "B", feature = "AVX512VL+AVX512F", vector_length = 128, encoding = "evex", broadcast = "tuple1_scalar" },
  { opcode = "EVEX.256.66.0F38.W1 59 /r", form = "VPBROADCASTQ ymm1{k1}{z}, xmm2/m64", op_en = "B", feature = "AVX512VL+AVX512F", vector_length = 256, encoding = "evex", broadcast = "tuple1_scalar" },
  { opcode = "EVEX.512.66.0F38.W1 59 /r", form = "VPBROADCASTQ zmm1{k1}{z}, xmm2/m64", op_en = "B", feature = "AVX512F", vector_length = 512, encoding = "evex", broadcast = "tuple1_scalar" },
  { opcode = "EVEX.128.66.0F38.W1 7C /r", form = "VPBROADCASTQ xmm1{k1}{z}, r64", op_en = "A", feature = "AVX512VL+AVX512F", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F38.W1 7C /r", form = "VPBROADCASTQ ymm1{k1}{z}, r64", op_en = "A", feature = "AVX512VL+AVX512F", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F38.W1 7C /r", form = "VPBROADCASTQ zmm1{k1}{z}, r64", op_en = "A", feature = "AVX512F", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "ModRM:r/m (r)"],
  B = ["ModRM:reg (w)", "ModRM:r/m (r)"]
}

lanes = { xmm = 2, ymm = 4, zmm = 8 }
flags_written = []
semantic = """
VPBROADCASTQ broadcasts the selected 64-bit source element to every destination
qword lane and clears the upper portion of the architectural vector when using
the VEX form.
"""
simd_fp_exceptions = []
other_exceptions = [
  "EVEX-encoded instructions use Type E6 class exception conditions",
  "GPR-source EVEX-encoded instructions use Type E7NM class exception conditions",
  "If VEX.vvvv != 1111B or EVEX.vvvv != 1111B, #UD",
  "If VEX.L = 0 for VPBROADCASTQ, #UD"
]

semantic_vex_256 = """
temp := SRC[63:0];
DEST[63:0]   := temp;
DEST[127:64] := temp;
DEST[191:128] := temp;
DEST[255:192] := temp;
DEST[MAXVL-1:256] := 0;
"""

semantic_evex = """
(KL, VL) = (2,128), (4,256), (8,512);
FOR j := 0 TO KL-1
    i := j * 64;
    IF k1[j] OR *no writemask*
        THEN DEST[i+63:i] := SRC[63:0]
        ELSE
            IF *merging-masking*
                THEN *DEST[i+63:i] remains unchanged*
                ELSE DEST[i+63:i] := 0
            FI
    FI;
ENDFOR;
DEST[MAXVL-1:VL] := 0;
"""

handler = "x86_vpbroadcastq"
jit_lowering = "arm64_neon_dup_d"
fallback = "zig_lane_loop_broadcast_64"

neon_register_model = """
x86 xmm/ymm/zmm qword lanes are mapped into ARM64 vector temporaries. VPBROADCASTQ uses DUP (element) to broadcast a 64-bit value to all qword positions.
"""

neon_flag_model = """
No x86 flags are modified by VPBROADCASTQ.
"""

neon_assembly = """
dup vD.2d, xN
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, writemask, broadcast, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
