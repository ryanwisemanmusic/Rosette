// TABLE/XLAT.inc
// Source contract: XLAT — Table Look-up Translation (explicit-operand form).

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "TABLE/XLAT.inc"
x86_handler = "x86_xlat"
neon_lowering = "arm64_xlat"
lowering_kind = "arm64_documented_contract"

name = "XLAT"
aliases = []
category = "table_lookup"
feature = "base"

encodings = [
  { opcode = "D7", form = "XLAT m8", op_en = "ZO", feature = "base", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = ["N/A", "N/A", "N/A", "N/A"]
}

lanes = { scalar = 1 }
flags_written = []
floating_point_exceptions = []
other_exceptions = [
  "#GP(0) If a memory operand effective address is outside the CS, DS, ES, FS, or GS segment limit.",
  "#SS(0) If a memory operand effective address is outside the SS segment limit.",
  "#PF(fault-code) If a page fault occurs.",
  "#UD If the LOCK prefix is used."
]

semantic_general = """
Locates a byte entry in a table in memory using the contents of AL as a table index,
then copies the contents of the table entry back into AL. Table base address is DS:(E)BX (or RBX in 64-bit mode).
"""

handler = "x86_xlat"
jit_lowering = "arm64_xlat"
fallback = "zig_xlat"

neon_register_model = """
XLAT is an x86 table lookup instruction. No ARM64 NEON equivalent; handled via documented contract.
"""

neon_flag_model = """
None.
"""

neon_assembly = """
// NEON lowering: XLAT stub (table lookup)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
