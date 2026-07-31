// INSERT_EXTRACT/VPEXTRD.inc
// ARM64/NEON mirror generated from ISA/x86/INSERT_EXTRACT/VPEXTRD.inc.
// Source contract: VPEXTRD — simd_insert_extract.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INSERT_EXTRACT/VPEXTRD.inc"
x86_handler = "x86_vpextrd"
neon_lowering = "arm64_vpextrd"
lowering_kind = "arm64_documented_contract"

name = "VPEXTRD"
aliases = []
category = "simd_insert_extract"
feature = "avx"
element_type = "i32"
element_size = 32

encodings = [
  { opcode = "VEX.128.66.0F3A 16 /r ib", form = "VPEXTRD r32/m32, xmm1, imm8", op_en = "RMI", feature = "avx", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Extract Dword from XMM.
"""

handler = "x86_vpextrd"
jit_lowering = "arm64_vpextrd"
fallback = "zig_vpextrd"

neon_register_model = """
VPEXTRD is a simd_insert_extract instruction.
"""

neon_flag_model = """
VPEXTRD does not modify flags.
"""

neon_assembly = """
// NEON lowering: VPEXTRD stub (simd_insert_extract)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

