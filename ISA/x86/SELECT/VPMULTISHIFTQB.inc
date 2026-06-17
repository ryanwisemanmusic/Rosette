// SELECT/VPMULTISHIFTQB.inc
// Source contract: VPMULTISHIFTQB — avx512_vbmi.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SELECT/VPMULTISHIFTQB.inc"
x86_handler = "x86_vpmultishiftqb"
neon_lowering = "arm64_vpmultishiftqb"
lowering_kind = "arm64_documented_contract"

name = "VPMULTISHIFTQB"
aliases = []
category = "avx512_vbmi"
feature = "avx512_vbmi"
element_type = "i8"
element_size = 8

encodings = [
  { opcode = "EVEX.128.66.0F38.W1 83 /r", form = "VPMULTISHIFTQB xmm1{k1}{z}, xmm2, xmm3/m128/m64bcst", op_en = "A", feature = "avx512_vbmi", vector_length = 128, encoding = "evex" }
  { opcode = "EVEX.256.66.0F38.W1 83 /r", form = "VPMULTISHIFTQB ymm1{k1}{z}, ymm2, ymm3/m256/m64bcst", op_en = "A", feature = "avx512_vbmi", vector_length = 256, encoding = "evex" }
  { opcode = "EVEX.512.66.0F38.W1 83 /r", form = "VPMULTISHIFTQB zmm1{k1}{z}, zmm2, zmm3/m512/m64bcst", op_en = "A", feature = "avx512_vbmi", vector_length = 512, encoding = "evex" }
]

operand_encoding = {
  A = []
}

simd_fp_exceptions = []

semantic_general = """
Select packed unaligned bytes from quadword sources.
"""

handler = "x86_vpmultishiftqb"
jit_lowering = "arm64_vpmultishiftqb"
fallback = "zig_vpmultishiftqb"

neon_register_model = """
VPMULTISHIFTQB is a avx512_vbmi instruction.
"""

neon_flag_model = """
VPMULTISHIFTQB does not modify flags.
"""

neon_assembly = """
// NEON lowering: VPMULTISHIFTQB stub (avx512_vbmi)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
