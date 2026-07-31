// INSERT_EXTRACT/VEXTRACTF128.inc
// ARM64/NEON mirror generated from ISA/x86/INSERT_EXTRACT/VEXTRACTF128.inc.
// Source contract: VEXTRACTF128 — simd_insert_extract.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INSERT_EXTRACT/VEXTRACTF128.inc"
x86_handler = "x86_vextractf128"
neon_lowering = "arm64_vextractf128"
lowering_kind = "arm64_documented_contract"

name = "VEXTRACTF128"
aliases = []
category = "simd_insert_extract"
feature = "avx"
element_type = "none"
element_size = 128

encodings = [
  { opcode = "VEX.256.66.0F3A 19 /r ib", form = "VEXTRACTF128 xmm1/m128, ymm2, imm8", op_en = "RMI", feature = "avx", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Extract Packed Floating-Point Values.
"""

handler = "x86_vextractf128"
jit_lowering = "arm64_vextractf128"
fallback = "zig_vextractf128"

neon_register_model = """
VEXTRACTF128 is a simd_insert_extract instruction.
"""

neon_flag_model = """
VEXTRACTF128 does not modify flags.
"""

neon_assembly = """
// NEON lowering: VEXTRACTF128 stub (simd_insert_extract)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

