// BROADCAST/VPBROADCASTMW2D.inc
// Source contract: VPBROADCASTMW2D — Broadcast Mask Word to Dword Vector.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "BROADCAST/VPBROADCASTMW2D.inc"
x86_handler = "x86_vpbroadcastmw2d"
neon_lowering = "arm64_vpbroadcastmw2d"
lowering_kind = "arm64_documented_contract"

name = "VPBROADCASTMW2D"
aliases = []
category = "avx512_broadcast"
feature = "avx512cd"
element_type = "i32"
element_size = 32

encodings = [
  { opcode = "EVEX.128.F3.0F38.W0 3A /r", form = "VPBROADCASTMW2D xmm1, k1", op_en = "RM", feature = "avx512vl+avx512cd", vector_length = 0, encoding = "evex" },
  { opcode = "EVEX.256.F3.0F38.W0 3A /r", form = "VPBROADCASTMW2D ymm1, k1", op_en = "RM", feature = "avx512vl+avx512cd", vector_length = 0, encoding = "evex" },
  { opcode = "EVEX.512.F3.0F38.W0 3A /r", form = "VPBROADCASTMW2D zmm1, k1", op_en = "RM", feature = "avx512cd", vector_length = 0, encoding = "evex" }
]

operand_encoding = {
  RM = ["ModRM:reg (w)", "ModRM:r/m (r)"]
}

lanes = { xmm = 1, ymm = 1, zmm = 1 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "EVEX-encoded instruction, see Table 2-54, Type E6NF Class Exception Conditions."
]

semantic_general = """
Broadcasts the zero-extended low word of mask register k1 to each dword element of the destination.
"""

handler = "x86_vpbroadcastmw2d"
jit_lowering = "arm64_vpbroadcastmw2d"
fallback = "zig_vpbroadcastmw2d"

neon_register_model = """
VPBROADCASTMW2D is an AVX512 mask-to-vector broadcast operation.
"""

neon_flag_model = """
VPBROADCASTMW2D does not modify flags.
"""

neon_assembly = """
// NEON lowering: VPBROADCASTMW2D stub (broadcast mask word to dwords)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
