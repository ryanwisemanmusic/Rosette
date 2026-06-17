// COMPLEMENT/CMC.inc
// Source contract: CMC — flag_control.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "COMPLEMENT/CMC.inc"
x86_handler = "x86_cmc"
neon_lowering = "arm64_cmc"
lowering_kind = "arm64_documented_contract"

name = "CMC"
aliases = []
category = "flag_control"
feature = "x86_gpr"
element_type = "integer"
element_size = 0

encodings = [
  { opcode = "F5", form = "CMC", op_en = "ZO", feature = "x86_gpr", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

flags_written = ["CF"]
simd_fp_exceptions = []

semantic_general = """
Complement the CF flag in EFLAGS.
"""

handler = "x86_cmc"
jit_lowering = "arm64_cmc"
fallback = "zig_cmc"

neon_register_model = """
CMC is a flag_control instruction.
"""

neon_flag_model = """
CMC writes CF.
"""

neon_assembly = """
// ARM64: MSR nzcv, xTMP with EOR
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, and notes above are intentionally preserved as the source contract."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
