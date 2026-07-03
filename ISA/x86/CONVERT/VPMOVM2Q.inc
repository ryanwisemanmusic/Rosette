// CONVERT/VPMOVM2Q.inc
// Source contract: VPMOVM2Q — Convert Mask Register to Vector (Qword).

semantic = """
VPMOVM2Q: sets each quadword in dest vector xmm1 to all 1s or all 0s based on each bit in src mask k1.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/VPMOVM2Q.inc"
x86_handler = "x86_vpmovm2q"
neon_lowering = "arm64_neon_vpmovm2q"
lowering_kind = "neon_vector"

name = "VPMOVM2Q"
aliases = []
category = "simd_convert"
feature = "avx512dq"
element_type = "i64"
element_size = 64

encodings = [
  { opcode = "EVEX.128.F3.0F38.W1 38 /r", form = "VPMOVM2Q xmm1, k1", op_en = "RM", feature = "avx512dq+avx512vl", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.F3.0F38.W1 38 /r", form = "VPMOVM2Q ymm1, k1", op_en = "RM", feature = "avx512dq+avx512vl", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.F3.0F38.W1 38 /r", form = "VPMOVM2Q zmm1, k1", op_en = "RM", feature = "avx512dq", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  RM = ["ModRM:reg (w)", "ModRM:r/m (r)"]
}

lanes = { xmm = 2, ymm = 4, zmm = 8 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "EVEX-encoded instruction, see Table 2-55, Type E7NM Class Exception Conditions",
  "#UD if EVEX.vvvv != 1111B"
]

semantic_general = """
Converts mask register bits to quadword elements in a vector register.
Each destination quadword is set to all 1s if the corresponding source
mask bit is 1, otherwise all 0s.
"""

handler = "x86_vpmovm2q"
jit_lowering = "arm64_neon_vpmovm2q"
fallback = "zig_lane_loop_vpmovm2q"

neon_register_model = """
x86 XMM/YMM/ZMM mapped to ARM64 Vn. VPMOVM2Q is an AVX512DQ mask conversion.
"""

neon_flag_model = """
No x86 flags modified by VPMOVM2Q.
"""

neon_assembly = """
// NEON lowering: VPMOVM2Q stub (simd_convert)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
