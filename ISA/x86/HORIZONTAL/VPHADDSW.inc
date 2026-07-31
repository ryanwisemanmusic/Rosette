// HORIZONTAL/VPHADDSW.inc
// Source contract: VPHADDSW — simd_horizontal.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "HORIZONTAL/VPHADDSW.inc"
x86_handler = "x86_vphaddsw"
neon_lowering = "arm64_vphaddsw"
lowering_kind = "arm64_documented_contract"

name = "VPHADDSW"
aliases = []
category = "simd_horizontal"
feature = "avx"
element_type = "i16"
element_size = 16

encodings = [
  { opcode = "VEX.128.66.0F38 03 /r", form = "VPHADDSW xmm1, xmm2, xmm3/m128", op_en = "RVM", feature = "avx", vector_length = 0, encoding = "legacy" }
  { opcode = "VEX.256.66.0F38 03 /r", form = "VPHADDSW ymm1, ymm2, ymm3/m256", op_en = "RVM", feature = "avx", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}
simd_fp_exceptions = []

semantic_general = """
Packed Horizontal Add Saturated Word.
"""

handler = "x86_vphaddsw"
jit_lowering = "arm64_vphaddsw"
fallback = "zig_vphaddsw"

neon_register_model = """
VPHADDSW is a simd_horizontal instruction.
"""

neon_flag_model = """
VPHADDSW does not modify flags.
"""

neon_assembly = """
// NEON lowering: VPHADDSW stub (simd_horizontal)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

