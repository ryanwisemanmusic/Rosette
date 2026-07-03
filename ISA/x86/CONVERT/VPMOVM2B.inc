// CONVERT/VPMOVM2B.inc
// Source contract: VPMOVM2B — Convert Mask Register to Vector (Byte).

semantic = """
VPMOVM2B: sets each byte in dest vector xmm1 to all 1s or all 0s based on each bit in src mask k1.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/VPMOVM2B.inc"
x86_handler = "x86_vpmovm2b"
neon_lowering = "arm64_neon_vpmovm2b"
lowering_kind = "neon_vector"

name = "VPMOVM2B"
aliases = []
category = "simd_convert"
feature = "avx512bw"
element_type = "i8"
element_size = 8

encodings = [
  { opcode = "EVEX.128.F3.0F38.W0 28 /r", form = "VPMOVM2B xmm1, k1", op_en = "RM", feature = "avx512bw+avx512vl", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.F3.0F38.W0 28 /r", form = "VPMOVM2B ymm1, k1", op_en = "RM", feature = "avx512bw+avx512vl", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.F3.0F38.W0 28 /r", form = "VPMOVM2B zmm1, k1", op_en = "RM", feature = "avx512bw", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  RM = ["ModRM:reg (w)", "ModRM:r/m (r)"]
}

lanes = { xmm = 16, ymm = 32, zmm = 64 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "EVEX-encoded instruction, see Table 2-55, Type E7NM Class Exception Conditions",
  "#UD if EVEX.vvvv != 1111B"
]

semantic_general = """
Converts mask register bits to byte elements in a vector register.
Each destination byte is set to all 1s if the corresponding source
mask bit is 1, otherwise all 0s.
"""

handler = "x86_vpmovm2b"
jit_lowering = "arm64_neon_vpmovm2b"
fallback = "zig_lane_loop_vpmovm2b"

neon_register_model = """
x86 XMM/YMM/ZMM mapped to ARM64 Vn. VPMOVM2B is an AVX512BW mask conversion.
"""

neon_flag_model = """
No x86 flags modified by VPMOVM2B.
"""

neon_assembly = """
// NEON lowering: VPMOVM2B stub (simd_convert)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
