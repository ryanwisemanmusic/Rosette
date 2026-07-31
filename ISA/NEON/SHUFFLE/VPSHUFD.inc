// SHUFFLE/VPSHUFD.inc
// ARM64/NEON mirror generated from ISA/x86/SHUFFLE/VPSHUFD.inc.
// Source contract: VPSHUFD — simd_shuffle.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "SHUFFLE/VPSHUFD.inc"
x86_handler = "x86_vpshufd"
neon_lowering = "arm64_vpshufd"
lowering_kind = "arm64_documented_contract"

name = "VPSHUFD"
aliases = []
category = "simd_shuffle"
feature = "avx"
element_type = "i32"
element_size = 32

encodings = [
  { opcode = "VEX.128.66.0F 70 /r ib", form = "VPSHUFD xmm1, xmm2/m128, imm8", op_en = "RMI", feature = "avx", vector_length = 0, encoding = "legacy" }
  { opcode = "VEX.256.66.0F 70 /r ib", form = "VPSHUFD ymm1, ymm2/m256, imm8", op_en = "RMI", feature = "avx", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Shuffle Packed Doublewords.
"""

handler = "x86_vpshufd"
jit_lowering = "arm64_vpshufd"
fallback = "zig_vpshufd"

neon_register_model = """
VPSHUFD is a simd_shuffle instruction.
"""

neon_flag_model = """
VPSHUFD does not modify flags.
"""

neon_assembly = """
// NEON lowering: VPSHUFD stub (simd_shuffle)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

