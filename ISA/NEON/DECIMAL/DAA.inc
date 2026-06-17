// DECIMAL/DAA.inc
// ARM64/NEON mirror generated from ISA/x86/DECIMAL/DAA.inc.

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "DECIMAL/DAA.inc"
x86_handler = "x86_daa"
neon_lowering = "arm64_daa"
lowering_kind = "arm64_documented_contract"

name = "DAA"
aliases = []
category = "bcd"
feature = "x86_gpr"
element_type = "u8"
element_size = 8

encodings = [
  { opcode = "27", form = "DAA", op_en = "ZO", feature = "x86_gpr", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

flags_written = ["CF", "AF", "SF", "ZF", "PF"]
simd_fp_exceptions = []

semantic_general = """
Decimal adjust AL after addition (packed BCD).
"""

handler = "x86_daa"
jit_lowering = "arm64_daa"
fallback = "zig_daa"

neon_register_model = """
DAA is a bcd instruction.
"""

neon_flag_model = """
DAA writes CF, AF, SF, ZF, PF.
"""

neon_assembly = """
// NEON lowering: BCD adjust stub (x86-specific, not available on ARM64)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
