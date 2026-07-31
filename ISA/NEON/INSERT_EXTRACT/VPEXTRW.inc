// INSERT_EXTRACT/VPEXTRW.inc
// ARM64/NEON mirror generated from ISA/x86/INSERT_EXTRACT/VPEXTRW.inc.
// Source contract: VPEXTRW — simd_insert_extract.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INSERT_EXTRACT/VPEXTRW.inc"
x86_handler = "x86_vpextrw"
neon_lowering = "arm64_vpextrw"
lowering_kind = "arm64_documented_contract"

name = "VPEXTRW"
aliases = []
category = "simd_insert_extract"
feature = "avx"
element_type = "i16"
element_size = 16

encodings = [
  { opcode = "VEX.128.66.0F3A 15 /r ib", form = "VPEXTRW r32/m16, xmm1, imm8", op_en = "RMI", feature = "avx", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

simd_fp_exceptions = []

semantic_general = """
Extract Word from XMM.
"""

handler = "x86_vpextrw"
jit_lowering = "arm64_vpextrw"
fallback = "zig_vpextrw"

neon_register_model = """
VPEXTRW is a simd_insert_extract instruction.
"""

neon_flag_model = """
VPEXTRW does not modify flags.
"""

neon_assembly = """
// NEON lowering: VPEXTRW stub (simd_insert_extract)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

