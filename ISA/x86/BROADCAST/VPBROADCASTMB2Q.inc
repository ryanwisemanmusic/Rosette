// BROADCAST/VPBROADCASTMB2Q.inc
// Source contract: VPBROADCASTMB2Q — Broadcast Mask Byte to Qword Vector.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "BROADCAST/VPBROADCASTMB2Q.inc"
x86_handler = "x86_vpbroadcastmb2q"
neon_lowering = "arm64_vpbroadcastmb2q"
lowering_kind = "arm64_documented_contract"

name = "VPBROADCASTMB2Q"
aliases = []
category = "avx512_broadcast"
feature = "avx512cd"
element_type = "i64"
element_size = 64

encodings = [
  { opcode = "EVEX.128.F3.0F38.W1 2A /r", form = "VPBROADCASTMB2Q xmm1, k1", op_en = "RM", feature = "avx512vl+avx512cd", vector_length = 0, encoding = "evex" },
  { opcode = "EVEX.256.F3.0F38.W1 2A /r", form = "VPBROADCASTMB2Q ymm1, k1", op_en = "RM", feature = "avx512vl+avx512cd", vector_length = 0, encoding = "evex" },
  { opcode = "EVEX.512.F3.0F38.W1 2A /r", form = "VPBROADCASTMB2Q zmm1, k1", op_en = "RM", feature = "avx512cd", vector_length = 0, encoding = "evex" }
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
Broadcasts the zero-extended low byte of mask register k1 to each qword element of the destination.
"""

handler = "x86_vpbroadcastmb2q"
jit_lowering = "arm64_vpbroadcastmb2q"
fallback = "zig_vpbroadcastmb2q"

neon_register_model = """
VPBROADCASTMB2Q is an AVX512 mask-to-vector broadcast operation.
"""

neon_flag_model = """
VPBROADCASTMB2Q does not modify flags.
"""

neon_assembly = """
// NEON lowering: VPBROADCASTMB2Q stub (broadcast mask byte to qwords)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
