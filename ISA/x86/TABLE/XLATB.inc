// TABLE/XLATB.inc
// Source contract: XLATB — Table Look-up Translation (no-operand form).

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "TABLE/XLATB.inc"
x86_handler = "x86_xlatb"
neon_lowering = "arm64_xlatb"
lowering_kind = "arm64_documented_contract"

name = "XLATB"
aliases = []
category = "table_lookup"
feature = "base"

encodings = [
  { opcode = "D7", form = "XLATB", op_en = "ZO", feature = "base", vector_length = 0, encoding = "legacy", description = "16/32-bit address size" },
  { opcode = "REX.W + D7", form = "XLATB", op_en = "ZO", feature = "base", vector_length = 0, encoding = "legacy", description = "64-bit address size (REX.W)" }
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
Short form of XLAT. Sets AL to memory byte DS:[(E)BX + unsigned AL] (or [RBX + unsigned AL] in 64-bit mode).
"""

handler = "x86_xlatb"
jit_lowering = "arm64_xlatb"
fallback = "zig_xlatb"

neon_register_model = """
XLATB is an x86 table lookup instruction. No ARM64 NEON equivalent; handled via documented contract.
"""

neon_flag_model = """
None.
"""

neon_assembly = """
// NEON lowering: XLATB stub (table lookup, no-operand form)
"""

neon_notes = [
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
