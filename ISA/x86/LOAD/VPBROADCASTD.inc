// LOAD/VPBROADCASTD.inc
// VPBROADCASTD — Broadcast dword integer from source to all elements.

source_isa = "x86"
target_isa = "x86"
x86_table = "LOAD/VPBROADCASTD.inc"
x86_handler = "x86_vpbroadcastd"
neon_lowering = "arm64_neon_dup_s"
lowering_kind = "neon_vector"

name = "VPBROADCASTD"
aliases = []
category = "simd_broadcast_integer"
feature = "AVX2_AVX512F"
element_type = "i32"
element_size = 32

encodings = [
  { opcode = "VEX.128.66.0F38.W0 58 /r", form = "VPBROADCASTD xmm1, xmm2/m32", op_en = "A", feature = "AVX2", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.66.0F38.W0 58 /r", form = "VPBROADCASTD ymm1, xmm2/m32", op_en = "A", feature = "AVX2", vector_length = 256, encoding = "vex" },
  { opcode = "EVEX.128.66.0F38.W0 58 /r", form = "VPBROADCASTD xmm1{k1}{z}, xmm2/m32", op_en = "B", feature = "AVX512VL+AVX512F", vector_length = 128, encoding = "evex", broadcast = "tuple1_scalar" },
  { opcode = "EVEX.256.66.0F38.W0 58 /r", form = "VPBROADCASTD ymm1{k1}{z}, xmm2/m32", op_en = "B", feature = "AVX512VL+AVX512F", vector_length = 256, encoding = "evex", broadcast = "tuple1_scalar" },
  { opcode = "EVEX.512.66.0F38.W0 58 /r", form = "VPBROADCASTD zmm1{k1}{z}, xmm2/m32", op_en = "B", feature = "AVX512F", vector_length = 512, encoding = "evex", broadcast = "tuple1_scalar" },
  { opcode = "EVEX.128.66.0F38.W0 7C /r", form = "VPBROADCASTD xmm1{k1}{z}, r32", op_en = "A", feature = "AVX512VL+AVX512F", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.66.0F38.W0 7C /r", form = "VPBROADCASTD ymm1{k1}{z}, r32", op_en = "A", feature = "AVX512VL+AVX512F", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F38.W0 7C /r", form = "VPBROADCASTD zmm1{k1}{z}, r32", op_en = "A", feature = "AVX512F", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "ModRM:r/m (r)"],
  B = ["ModRM:reg (w)", "ModRM:r/m (r)"]
}

lanes = { xmm = 4, ymm = 8, zmm = 16 }
flags_written = []
semantic = """
VPBROADCASTD broadcasts the selected 32-bit source element to every destination
dword lane and clears the upper portion of the architectural vector when using
the VEX form.
"""
simd_fp_exceptions = []
other_exceptions = [
  "EVEX-encoded instructions use Type E6 class exception conditions",
  "GPR-source EVEX-encoded instructions use Type E7NM class exception conditions",
  "If VEX.vvvv != 1111B or EVEX.vvvv != 1111B, #UD"
]

semantic_legacy_128 = """
temp := SRC[31:0];
DEST[31:0]   := temp;
DEST[63:32]  := temp;
DEST[95:64]  := temp;
DEST[127:96] := temp;
DEST[MAXVL-1:128] := 0;
"""

semantic_vex_256 = """
temp := SRC[31:0];
DEST[31:0]    := temp;
DEST[63:32]   := temp;
DEST[95:64]   := temp;
DEST[127:96]  := temp;
DEST[159:128] := temp;
DEST[191:160] := temp;
DEST[223:192] := temp;
DEST[255:224] := temp;
DEST[MAXVL-1:256] := 0;
"""

semantic_evex = """
(KL, VL) = (4,128), (8,256), (16,512);
FOR j := 0 TO KL-1
    i := j * 32;
    IF k1[j] OR *no writemask*
        THEN DEST[i+31:i] := SRC[31:0]
        ELSE
            IF *merging-masking*
                THEN *DEST[i+31:i] remains unchanged*
                ELSE DEST[i+31:i] := 0
            FI
    FI;
ENDFOR;
DEST[MAXVL-1:VL] := 0;
"""

handler = "x86_vpbroadcastd"
jit_lowering = "arm64_neon_dup_s"
fallback = "zig_lane_loop_broadcast_32"

neon_register_model = """
x86 xmm/ymm/zmm dword lanes are mapped into ARM64 vector temporaries. VPBROADCASTD uses DUP (element) to broadcast a 32-bit value to all dword positions.
"""

neon_flag_model = """
No x86 flags are modified by VPBROADCASTD.
"""

neon_assembly = """
dup vD.4s, wN
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, writemask, broadcast, or implicit-operand behavior.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
