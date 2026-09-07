// INSERT_EXTRACT/VEXTRACTI32X4.inc
// Source contract: VEXTRACTI32X4 — extract one 128-bit integer lane.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INSERT_EXTRACT/VEXTRACTI32X4.inc"
x86_handler = "x86_vextracti32x4"
neon_lowering = "arm64_vextracti32x4"
lowering_kind = "arm64_documented_contract"

name = "VEXTRACTI32X4"
aliases = []
category = "simd_insert_extract"
feature = "avx512f+avx512vl"
element_type = "i32"
element_size = 32

encodings = [
  { opcode = "EVEX.256.66.0F3A.W0 39 /r ib", form = "VEXTRACTI32X4 xmm1/m128{k1}{z}, ymm2, imm8", op_en = "A", feature = "avx512f+avx512vl", vector_length = 256, encoding = "evex" },
  { opcode = "EVEX.512.66.0F3A.W0 39 /r ib", form = "VEXTRACTI32X4 xmm1/m128{k1}{z}, zmm2, imm8", op_en = "A", feature = "avx512f", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:r/m (w)", "ModRM:reg (r)", "imm8"]
}
flags_written = []
simd_fp_exceptions = []

semantic_general = """
Extract the 128-bit integer lane selected by imm8[0] from the source vector.
The destination is zero-extended above the written 128-bit lane. EVEX writemask
merging/zeroing applies to the extracted 128-bit destination lane.
"""

handler = "x86_vextracti32x4"
jit_lowering = "arm64_vextracti32x4"
fallback = "zig_vextracti32x4"

neon_register_model = """
XMM/YMM/ZMM integer lanes are held in the shared 32-register vector file.
"""

neon_flag_model = """
VEXTRACTI32X4 does not modify x86 flags.
"""

neon_assembly = """
// NEON lowering: select one 128-bit lane and apply EVEX mask semantics.
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
