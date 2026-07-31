// INSERT_EXTRACT/VPEXTRB.inc
// ARM64/NEON mirror generated from ISA/x86/INSERT_EXTRACT/VPEXTRB.inc.
// Source contract: VPEXTRB — simd_insert_extract.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INSERT_EXTRACT/VPEXTRB.inc"
x86_handler = "x86_vpextrb"
neon_lowering = "arm64_vpextrb"
lowering_kind = "arm64_documented_contract"

name = "VPEXTRB"
aliases = []
category = "simd_insert_extract"
feature = "avx"
element_type = "i8"
element_size = 8

encodings = [
  { opcode = "VEX.128.66.0F3A 14 /r ib", form = "VPEXTRB r32/m8, xmm1, imm8", op_en = "RMI", feature = "avx", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Extract Byte from XMM.
"""

handler = "x86_vpextrb"
jit_lowering = "arm64_vpextrb"
fallback = "zig_vpextrb"

neon_register_model = """
VPEXTRB is a simd_insert_extract instruction.
"""

neon_flag_model = """
VPEXTRB does not modify flags.
"""

neon_assembly = """
// NEON lowering: VPEXTRB stub (simd_insert_extract)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

