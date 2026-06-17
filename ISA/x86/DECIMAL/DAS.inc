// DECIMAL/DAS.inc
// Source contract: DAS — bcd.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "DECIMAL/DAS.inc"
x86_handler = "x86_das"
neon_lowering = "arm64_das"
lowering_kind = "arm64_documented_contract"

name = "DAS"
aliases = []
category = "bcd"
feature = "x86_gpr"
element_type = "u8"
element_size = 8

encodings = [
  { opcode = "2F", form = "DAS", op_en = "ZO", feature = "x86_gpr", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

flags_written = ["CF", "AF", "SF", "ZF", "PF"]
simd_fp_exceptions = []

semantic_general = """
Decimal adjust AL after subtraction (packed BCD).
"""

handler = "x86_das"
jit_lowering = "arm64_das"
fallback = "zig_das"

neon_register_model = """
DAS is a bcd instruction.
"""

neon_flag_model = """
DAS writes CF, AF, SF, ZF, PF.
"""

neon_assembly = """
// NEON lowering: BCD adjust stub (x86-specific, not available on ARM64)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, and notes above are intentionally preserved as the source contract."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
