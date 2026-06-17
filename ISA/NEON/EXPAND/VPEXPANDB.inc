// EXPAND/VPEXPANDB.inc
// ARM64/NEON mirror generated from ISA/x86/EXPAND/VPEXPANDB.inc.
// Source contract: VPEXPANDB — avx512_vbmi2.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "EXPAND/VPEXPANDB.inc"
x86_handler = "x86_vpexpandb"
neon_lowering = "arm64_vpexpandb"
lowering_kind = "arm64_documented_contract"

name = "VPEXPANDB"
aliases = []
category = "avx512_vbmi2"
feature = "avx512_vbmi2"
element_type = "i8"
element_size = 8

encodings = [
  { opcode = "EVEX.128.66.0F38.W0 62 /r", form = "VPEXPANDB xmm1{k1}{z}, m128", op_en = "A", feature = "avx512_vbmi2", vector_length = 128, encoding = "evex" }
  { opcode = "EVEX.256.66.0F38.W0 62 /r", form = "VPEXPANDB ymm1{k1}{z}, m256", op_en = "A", feature = "avx512_vbmi2", vector_length = 256, encoding = "evex" }
  { opcode = "EVEX.512.66.0F38.W0 62 /r", form = "VPEXPANDB zmm1{k1}{z}, m512", op_en = "A", feature = "avx512_vbmi2", vector_length = 512, encoding = "evex" }
  { opcode = "EVEX.128.66.0F38.W0 62 /r", form = "VPEXPANDB xmm1{k1}{z}, xmm2", op_en = "B", feature = "avx512_vbmi2", vector_length = 128, encoding = "evex" }
  { opcode = "EVEX.256.66.0F38.W0 62 /r", form = "VPEXPANDB ymm1{k1}{z}, ymm2", op_en = "B", feature = "avx512_vbmi2", vector_length = 256, encoding = "evex" }
  { opcode = "EVEX.512.66.0F38.W0 62 /r", form = "VPEXPANDB zmm1{k1}{z}, zmm2", op_en = "B", feature = "avx512_vbmi2", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  A = []
  B = []
}

simd_fp_exceptions = []

semantic_general = """
Expand packed byte values from sparse to dense elements.
"""

handler = "x86_vpexpandb"
jit_lowering = "arm64_vpexpandb"
fallback = "zig_vpexpandb"

neon_register_model = """
VPEXPANDB is a avx512_vbmi2 instruction.
"""

neon_flag_model = """
VPEXPANDB does not modify flags.
"""

neon_assembly = """
// NEON lowering: VPEXPANDB stub (avx512_vbmi2)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
