// COUNT/VPLZCNTQ.inc
// ARM64/NEON mirror generated from ISA/x86/COUNT/VPLZCNTQ.inc.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "COUNT/VPLZCNTQ.inc"
x86_handler = "x86_vplzcntq"
neon_lowering = "arm64_vplzcntq"
lowering_kind = "arm64_documented_contract"

name = "VPLZCNTQ"
aliases = []
category = "bit_count"
feature = "AVX512CD"
element_type = "i64"
element_size = 64

encodings = [
  { opcode = "EVEX.128.66.0F38.W1 44 /r", form = "VPLZCNTQ xmm1 {k1}{z}, xmm2/m128/m64bcst", op_en = "A", feature = "AVX512VL AVX512CD", vector_length = 0, encoding = "legacy" },
  { opcode = "EVEX.256.66.0F38.W1 44 /r", form = "VPLZCNTQ ymm1 {k1}{z}, ymm2/m256/m64bcst", op_en = "A", feature = "AVX512VL AVX512CD", vector_length = 0, encoding = "legacy" },
  { opcode = "EVEX.512.66.0F38.W1 44 /r", form = "VPLZCNTQ zmm1 {k1}{z}, zmm2/m512/m64bcst", op_en = "A", feature = "AVX512CD", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "ModRM:r/m (r)"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
Count the number of leading zero bits in each qword element using writemask k1.
"""

handler = "x86_vplzcntq"
jit_lowering = "arm64_vplzcntq"
fallback = "zig_vplzcntq"

neon_register_model = """
VPLZCNTQ is a bit_count instruction. ARM64 CLZ/RBIT available.
"""

neon_flag_model = """
No x86 flags modified by VPLZCNTQ.
"""

neon_assembly = """
// NEON lowering: VCLZ on 64-bit lanes
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
