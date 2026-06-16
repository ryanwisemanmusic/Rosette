// HALT/HLT.inc
// ARM64/NEON mirror generated from ISA/x86/HALT/HLT.inc.

semantic = """
HLT: halt the processor until an external interrupt or reset.
Category: system.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "HALT/HLT.inc"
x86_handler = "x86_hlt"
neon_lowering = "arm64_hlt"
lowering_kind = "arm64_hlt"

name = "HLT"
aliases = []
category = "system"
feature = "x86_gpr"
element_type = "none"
element_size = 0

encodings = [
  { opcode = "F4", form = "HLT", op_en = "ZO", feature = "x86_gpr", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = []
}

lanes = { xmm = 0, ymm = 0 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "#UD if CPL != 0"
]

semantic_general = """
Enter Halt state;
Stop instruction execution until an external interrupt or reset occurs.
"""

handler = "x86_hlt"
jit_lowering = "arm64_hlt"
fallback = "zig_hlt"

neon_register_model = """
No register modification; HLT does not write any architectural state.
"""

neon_flag_model = """
No x86 flags modified by HLT.
"""

neon_assembly = """
// NEON lowering: wfi (wait for interrupt)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
