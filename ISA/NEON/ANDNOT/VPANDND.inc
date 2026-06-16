// ANDNOT/VPANDND.inc
// ARM64/NEON mirror generated from ISA/x86/ANDNOT/VPANDND.inc.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "ANDNOT/VPANDND.inc"
x86_handler = "x86_vpandnd"
neon_lowering = "arm64_vpandnd"
lowering_kind = "arm64_documented_contract"

name = "VPANDND"
aliases = []
category = "bitwise"
feature = "AVX512F"
element_type = "i32"
element_size = 32

encodings = [
  { opcode = "EVEX.128.66.0F.W0 DF /r", form = "VPANDND xmm1 {k1}{z}, xmm2, xmm3/m128/m32bcst", op_en = "C", feature = "AVX512VL AVX512F", vector_length = 0, encoding = "legacy" },
  { opcode = "EVEX.256.66.0F.W0 DF /r", form = "VPANDND ymm1 {k1}{z}, ymm2, ymm3/m256/m32bcst", op_en = "C", feature = "AVX512VL AVX512F", vector_length = 0, encoding = "legacy" },
  { opcode = "EVEX.512.66.0F.W0 DF /r", form = "VPANDND zmm1 {k1}{z}, zmm2, zmm3/m512/m32bcst", op_en = "C", feature = "AVX512F", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  C = ["ModRM:reg (w)", "EVEX.vvvv (r)", "ModRM:r/m (r)"]
}

flags_written = []
simd_fp_exceptions = []

semantic_general = """
Bitwise AND NOT of packed dword integers with writemask.
"""

handler = "x86_vpandnd"
jit_lowering = "arm64_vpandnd"
fallback = "zig_vpandnd"

neon_register_model = """
VPANDND is a bitwise instruction. ARM64 MVN/BIC available.
"""

neon_flag_model = """
No x86 flags modified by VPANDND.
"""

neon_assembly = """
// NEON lowering: BIC on 32-bit lanes
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
