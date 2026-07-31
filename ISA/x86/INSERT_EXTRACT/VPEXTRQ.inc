// INSERT_EXTRACT/VPEXTRQ.inc
// Source contract: VPEXTRQ — simd_insert_extract.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "INSERT_EXTRACT/VPEXTRQ.inc"
x86_handler = "x86_vpextrq"
neon_lowering = "arm64_vpextrq"
lowering_kind = "arm64_documented_contract"

name = "VPEXTRQ"
aliases = []
category = "simd_insert_extract"
feature = "avx"
element_type = "i64"
element_size = 64

encodings = [
  { opcode = "VEX.128.66.0F3A 16 /r ib", form = "VPEXTRQ r64/m64, xmm1, imm8", op_en = "RMI", feature = "avx", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}
simd_fp_exceptions = []

semantic_general = """
Extract Qword from XMM.
"""

handler = "x86_vpextrq"
jit_lowering = "arm64_vpextrq"
fallback = "zig_vpextrq"

neon_register_model = """
VPEXTRQ is a simd_insert_extract instruction.
"""

neon_flag_model = """
VPEXTRQ does not modify flags.
"""

neon_assembly = """
// NEON lowering: VPEXTRQ stub (simd_insert_extract)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]

