// CONVERT/VPMOVB2M.inc
// Source contract: VPMOVB2M — Convert Vector Register to Mask (Byte).

semantic = """
VPMOVB2M: sets each bit in dest mask k1 based on MSB of each byte in src.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "CONVERT/VPMOVB2M.inc"
x86_handler = "x86_vpmovb2m"
neon_lowering = "arm64_neon_vpmovb2m"
lowering_kind = "neon_vector"

name = "VPMOVB2M"
aliases = []
category = "simd_convert"
feature = "avx512bw"
element_type = "i8"
element_size = 8

encodings = [
  { opcode = "EVEX.128.F3.0F38.W0 29 /r", form = "VPMOVB2M k1, xmm1", op_en = "RM", feature = "avx512bw+avx512vl", vector_length = 128, encoding = "evex" },
  { opcode = "EVEX.256.F3.0F38.W0 29 /r", form = "VPMOVB2M k1, ymm1", op_en = "RM", feature = "avx512bw+avx512vl", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.F3.0F38.W0 29 /r", form = "VPMOVB2M k1, zmm1", op_en = "RM", feature = "avx512bw", vector_length = 512, encoding = "evex" }
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
Converts byte elements of a vector register to mask register bits.
Each destination bit is set to 1 if the MSB of the corresponding
source byte is 1, otherwise 0.
"""

handler = "x86_vpmovb2m"
jit_lowering = "arm64_neon_vpmovb2m"
fallback = "zig_lane_loop_vpmovb2m"

neon_register_model = """
x86 XMM/YMM/ZMM mapped to ARM64 Vn. VPMOVB2M is an AVX512BW mask conversion.
"""

neon_flag_model = """
No x86 flags modified by VPMOVB2M.
"""

neon_assembly = """
// NEON lowering: VPMOVB2M stub (simd_convert)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
