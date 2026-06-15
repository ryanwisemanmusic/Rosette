// LOOP/PAUSE.inc
// ARM64/NEON translation mirror generated from ISA/x86/LOOP/PAUSE.inc.
// Source contract: PAUSE — Spin loop hint; execute next instruction with delay.

semantic = """
PAUSE: preserve the operation and form-specific semantic blocks.
Category: sync.
"""

source_isa = "x86"
target_isa = "arm64_neon"
x86_table = "LOOP/PAUSE.inc"
x86_handler = "x86_pause"
neon_lowering = "arm64_pause"
lowering_kind = "arm64_nop"

name = "PAUSE"
aliases = []
category = "sync"
feature = "x86_gpr"
element_type = "none"
element_size = 0

encodings = [
  { opcode = "F3 90", form = "PAUSE", op_en = "ZO", feature = "x86_gpr", vector_length = 0, encoding = "legacy" }
]

operand_encoding = {
  ZO = ["N/A"]
}

lanes = { xmm = 0, ymm = 0 }
flags_written = []
simd_fp_exceptions = []
other_exceptions = [
  "#UD if LOCK prefix"
]

semantic_general = """
Execute next instruction with delay; spin loop hint.
"""

handler = "x86_pause"
jit_lowering = "arm64_pause"
fallback = "zig_pause"

neon_register_model = """
PAUSE is a hint instruction; no registers modified.
"""

neon_flag_model = """
No x86 flags modified by PAUSE.
"""

neon_assembly = """
// NEON lowering: yield (or nop equivalent)
"""

neon_notes = [
  "The x86 encoding, operands, semantic text, exceptions, and notes above are intentionally preserved as the source contract.",
  "Runtime ABI validation checks both the x86 table shape and this NEON lowering shape."
]

abi_contract = ["x86_table_shape", "neon_mirror_shape", "arm64_lowering_shape", "full_scope_preserved"]
