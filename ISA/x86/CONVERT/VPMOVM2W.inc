// CONVERT/VPMOVM2W.inc
// Source contract: VPMOVM2W — Convert Mask Register to Vector (Word).

semantic = """
VPMOVM2W: sets each word in dest vector xmm1 to all 1s or all 0s based on each bit in src mask k1.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/VPMOVM2W.inc"
x86_handler = "x86_vpmovm2w"
neon_lowering = "arm64_neon_vpmovm2w"
lowering_kind = "neon_vector"

name = "VPMOVM2W"
aliases = []
category = "simd_convert"
feature = "avx512bw"
element_type = "i16"
element_size = 16

encodings = [
  { opcode = "EVEX.128.F3.0F38.W1 28 /r", form = "VPMOVM2W xmm1, k1", op_en = "RM", feature = "avx512bw+avx512vl", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.F3.0F38.W1 28 /r", form = "VPMOVM2W ymm1, k1", op_en = "RM", feature = "avx512bw+avx512vl", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.F3.0F38.W1 28 /r", form = "VPMOVM2W zmm1, k1", op_en = "RM", feature = "avx512bw", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  RM = ["ModRM:reg (w)", "ModRM:r/m (r)"]
}

lanes = { xmm = 8, ymm = 16, zmm = 32 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "EVEX-encoded instruction, see Table 2-55, Type E7NM Class Exception Conditions",
  "#UD if EVEX.vvvv != 1111B"
]

semantic_general = """
Converts mask register bits to word elements in a vector register.
Each destination word is set to all 1s if the corresponding source
mask bit is 1, otherwise all 0s.
"""

handler = "x86_vpmovm2w"
jit_lowering = "arm64_neon_vpmovm2w"
fallback = "zig_lane_loop_vpmovm2w"

neon_register_model = """
x86 XMM/YMM/ZMM mapped to ARM64 Vn. VPMOVM2W is an AVX512BW mask conversion.
"""

neon_flag_model = """
No x86 flags modified by VPMOVM2W.
"""

neon_assembly = """
// NEON lowering: VPMOVM2W stub (simd_convert)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
