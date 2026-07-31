// HORIZONTAL/VPHADDW.inc
// ARM64/NEON mirror generated from ISA/x86/HORIZONTAL/VPHADDW.inc.
// Source contract: VPHADDW — simd_horizontal.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "HORIZONTAL/VPHADDW.inc"
x86_handler = "x86_vphaddw"
neon_lowering = "arm64_vphaddw"
lowering_kind = "arm64_documented_contract"

name = "VPHADDW"
aliases = []
category = "simd_horizontal"
feature = "avx"
element_type = "i16"
element_size = 16

encodings = [
  { opcode = "VEX.128.66.0F38 01 /r", form = "VPHADDW xmm1, xmm2, xmm3/m128", op_en = "RVM", feature = "avx", vector_length = 0, encoding = "legacy" }
  { opcode = "VEX.256.66.0F38 01 /r", form = "VPHADDW ymm1, ymm2, ymm3/m256", op_en = "RVM", feature = "avx", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Packed Horizontal Add Word.
"""

handler = "x86_vphaddw"
jit_lowering = "arm64_vphaddw"
fallback = "zig_vphaddw"

neon_register_model = """
VPHADDW is a simd_horizontal instruction.
"""

neon_flag_model = """
VPHADDW does not modify flags.
"""

neon_assembly = """
// NEON lowering: VPHADDW stub (simd_horizontal)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

