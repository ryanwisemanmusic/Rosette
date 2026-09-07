// INSERT_EXTRACT/VEXTRACTI64X4.inc
// Source contract: VEXTRACTI64X4 — extract one 256-bit integer lane.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INSERT_EXTRACT/VEXTRACTI64X4.inc"
x86_handler = "x86_vextracti64x4"
neon_lowering = "arm64_vextracti64x4"
lowering_kind = "arm64_documented_contract"

name = "VEXTRACTI64X4"
aliases = []
category = "simd_insert_extract"
feature = "avx512f+avx512dq"
element_type = "i64"
element_size = 64

encodings = [
  { opcode = "EVEX.512.66.0F3A.W1 3B /r ib", form = "VEXTRACTI64X4 ymm1/m256{k1}{z}, zmm2, imm8", op_en = "A", feature = "avx512f+avx512dq", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  A = ["ModRM:r/m (w)", "ModRM:reg (r)", "imm8"]
}
flags_written = []
simd_fp_exceptions = []

semantic_general = """
Extract the 256-bit integer lane selected by imm8[0] from the source ZMM.
The destination is cleared above the written lane; EVEX writemask semantics
apply to the destination lane.
"""

handler = "x86_vextracti64x4"
jit_lowering = "arm64_vextracti64x4"
fallback = "zig_vextracti64x4"

neon_register_model = """
ZMM integer state is represented as two 256-bit halves in the shared vector
register file and can be selected without relying on host AVX-512 hardware.
"""

neon_flag_model = """
VEXTRACTI64X4 does not modify x86 flags.
"""

neon_assembly = """
// NEON lowering: select one 256-bit lane and apply EVEX mask semantics.
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
