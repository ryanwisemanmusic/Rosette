// COMPUTE/RCPPS.inc
// ARM64/NEON translation mirror generated from ISA/x86/COMPUTE/RCPPS.inc.
// Source contract: RCPPS/VRCPPS — Compute Reciprocals of Packed Single Precision.

semantic = """
RCPPS: preserve the operation and form-specific semantic blocks.
Category: simd_floating_point.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "COMPUTE/RCPPS.inc"
x86_handler = "x86_rcpps"
neon_lowering = "arm64_rcpps"
lowering_kind = "arm64_documented_contract"

name = "RCPPS"
aliases = ["VRCPPS"]
category = "simd_floating_point"
feature = "SSE_AVX"
element_type = "f32"
element_size = 32

encodings = [
  { opcode = "NP 0F 53 /r", form = "RCPPS xmm1, xmm2/m128", op_en = "A", feature = "SSE", vector_length = 128, encoding = "legacy_sse" },
  { opcode = "VEX.128.0F.WIG 53 /r", form = "VRCPPS xmm1, xmm2, xmm3/m128", op_en = "B", feature = "AVX", vector_length = 128, encoding = "vex" },
  { opcode = "VEX.256.0F.WIG 53 /r", form = "VRCPPS ymm1, ymm2, ymm3/m256", op_en = "B", feature = "AVX", vector_length = 256, encoding = "vex" }
]

operand_encoding = {
  A = ["ModRM:reg (r,w)", "ModRM:r/m (r)"],
  B = ["ModRM:reg (w)", "VEX.vvvv (r)", "ModRM:r/m (r)"]
}

lanes = { xmm = 4, ymm = 8 }
flags_written = []
simd_fp_exceptions = [
  "Non-VEX encoded instruction uses Type 2 class exception conditions",
  "VEX encoded instruction uses Type 2 class exception conditions"
]
other_exceptions = [
  "#UD if VEX.W=1",
  "#UD if LOCK prefix"
]

semantic_legacy_128 = """
DEST[31:0]   = APPROXIMATE_RECIPROCAL(SRC[31:0]);
DEST[63:32]  = APPROXIMATE_RECIPROCAL(SRC[63:32]);
DEST[95:64]  = APPROXIMATE_RECIPROCAL(SRC[95:64]);
DEST[127:96] = APPROXIMATE_RECIPROCAL(SRC[127:96]);
DEST[MAXVL-1:128] unchanged;
"""

semantic_vex_128 = """
DEST[31:0]   = APPROXIMATE_RECIPROCAL(SRC2[31:0]);
DEST[63:32]  = APPROXIMATE_RECIPROCAL(SRC2[63:32]);
DEST[95:64]  = APPROXIMATE_RECIPROCAL(SRC2[95:64]);
DEST[127:96] = APPROXIMATE_RECIPROCAL(SRC2[127:96]);
DEST[MAXVL-1:128] = 0;
"""

semantic_vex_256 = """
for lane in 0..7:
    i = lane * 32;
    DEST[i+31:i] = APPROXIMATE_RECIPROCAL(SRC2[i+31:i]);
DEST[MAXVL-1:256] = 0;
"""

handler = "x86_rcpps"
jit_lowering = "arm64_rcpps"
fallback = "zig_lane_loop_rcp_approx"

neon_register_model = """
x86 xmm/ymm f32 lanes mapped to ARM64 V registers.
RCPPS reciprocal estimate maps to ARM64 FRECPE instruction.
"""

neon_flag_model = """
No x86 flags are modified by RCPPS/VRCPPS.
MXCSR exception flags may be updated per the x86 specification.
"""

neon_assembly = """
// NEON lowering: frecpe vD.4s, vN.4s (or vD.2d, vN.2d for ymm via pairwise)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "The ARM64/NEON lowering must not weaken the x86 register, flag, exception, lock-prefix, MXCSR, or implicit-operand behavior.",
  "ARM64 FRECPE provides a 12-bit-accurate reciprocal estimate matching x86 RCPPS precision.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
