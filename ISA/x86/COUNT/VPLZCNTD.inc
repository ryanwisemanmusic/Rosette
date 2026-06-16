// COUNT/VPLZCNTD.inc
// Source contract: VPLZCNTD — bit_count.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "COUNT/VPLZCNTD.inc"
x86_handler = "x86_vplzcntd"
neon_lowering = "arm64_vplzcntd"
lowering_kind = "arm64_documented_contract"

name = "VPLZCNTD"
aliases = []
category = "bit_count"
feature = "AVX512CD"
element_type = "i32"
element_size = 32

encodings = [
  { opcode = "EVEX.128.66.0F38.W0 44 /r", form = "VPLZCNTD xmm1 {k1}{z}, xmm2/m128/m32bcst", op_en = "A", feature = "AVX512VL AVX512CD", vector_length = 0, encoding = "legacy" },
  { opcode = "EVEX.256.66.0F38.W0 44 /r", form = "VPLZCNTD ymm1 {k1}{z}, ymm2/m256/m32bcst", op_en = "A", feature = "AVX512VL AVX512CD", vector_length = 0, encoding = "legacy" },
  { opcode = "EVEX.512.66.0F38.W0 44 /r", form = "VPLZCNTD zmm1 {k1}{z}, zmm2/m512/m32bcst", op_en = "A", feature = "AVX512CD", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  A = ["ModRM:reg (w)", "ModRM:r/m (r)"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
Count the number of leading zero bits in each dword element using writemask k1.
"""

handler = "x86_vplzcntd"
jit_lowering = "arm64_vplzcntd"
fallback = "zig_vplzcntd"

neon_register_model = """
x86 GPR/XMM/YMM/ZMM mapped to ARM64 equivalents. VPLZCNTD is a bit_count instruction.
"""

neon_flag_model = """
No x86 flags modified by VPLZCNTD.
"""

neon_assembly = """
// NEON lowering: VCLZ on 32-bit lanes
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, and notes above are intentionally preserved as the source contract."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
